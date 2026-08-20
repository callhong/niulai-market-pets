import AppKit
import Combine
import NiuLaiMarketPets
import SwiftUI
import UserNotifications

@main
struct NiuLaiMarketPetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class ContextHostingView: NSHostingView<AnyView> {
    var contextMenuBuilder: (() -> NSMenu)?

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuBuilder?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

@MainActor
final class MarketMenuRowView: NSView {
    private let checkLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let target: MarketTarget

    init(target: MarketTarget, snapshot: MarketSnapshot, selected: Bool) {
        self.target = target
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        checkLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        checkLabel.alignment = .center
        nameLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        valueLabel.alignment = .right
        for label in [checkLabel, nameLabel, valueLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 286),
            heightAnchor.constraint(equalToConstant: 24),
            checkLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkLabel.widthAnchor.constraint(equalToConstant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: checkLabel.trailingAnchor, constant: 4),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        update(snapshot: snapshot, selected: selected)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(snapshot: MarketSnapshot, selected: Bool) {
        checkLabel.stringValue = selected ? "✓" : ""
        nameLabel.stringValue = target.name
        let now = Date()
        let stale = snapshot.isStale(at: now)
        valueLabel.stringValue = snapshot.quote.map { MarketRules.signedPercent($0.percent) } ?? "--"
        valueLabel.textColor = NSColor(hex: snapshot.tone(at: now).colorHex)
        nameLabel.textColor = stale ? NSColor.secondaryLabelColor : NSColor.labelColor
        checkLabel.textColor = NSColor.controlAccentColor
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let number = UInt64(value, radix: 16) ?? 0x8A8F98
        self.init(
            srgbRed: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: 1
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = ControllerModel()
    private var panel: FloatingPanel?
    private var contextHostingView: ContextHostingView?
    private var statusItem: NSStatusItem?
    private var statusSummaryItem: NSMenuItem?
    private var statusShapeItems: [NSMenuItem] = []
    private var statusTargetItems: [NSMenuItem] = []
    private var statusPollingItem: NSMenuItem?
    private var statusScaleItem: NSMenuItem?
    private var statusSpeechScaleItem: NSMenuItem?
    private var statusMuteItem: NSMenuItem?
    private var statusPillItem: NSMenuItem?
    private var scalePopover: NSPopover?
    private var speechScalePopover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        model.start()
        observeLayoutChanges()
        requestNotifications()
        setupStatusItem()
        if model.panelVisible { showPanel() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func showPanel() {
        if panel == nil {
            let size = FloatingLayout.size(for: model.petScalePercent)
            let frame = NSRect(origin: .zero, size: size)
            let created = FloatingPanel(frame: frame)
            let host = ContextHostingView(rootView: AnyView(
                ControllerView(model: model, onToggleVisibility: { [weak self] in
                    self?.togglePanel()
                })
            ))
            host.contextMenuBuilder = { [weak self] in
                self?.makeContextMenu() ?? NSMenu()
            }
            created.contentView = host
            created.delegate = self
            contextHostingView = host
            panel = created
        }
        guard let panel else { return }
        if let x = model.panelX, let y = model.panelY {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 24,
                y: visible.minY + 24
            ))
        }
        resizePanel(keepingCenter: false)
        panel.orderFrontRegardless()
        model.setPanelVisible(true)
    }

    func hidePanel() {
        guard let panel else {
            model.setPanelVisible(false)
            return
        }
        let origin = panel.frame.origin
        model.updatePanelPosition(x: origin.x, y: origin.y)
        model.setPanelVisible(false)
        panel.orderOut(nil)
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true { hidePanel() } else { showPanel() }
    }

    @objc private func selectShapeFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        if value == ControlMode.auto.rawValue {
            model.selectAuto()
        } else if let pet = PetID(rawValue: value) {
            model.selectManual(pet)
        }
    }

    @objc private func selectTargetFromMenu(_ sender: NSMenuItem) {
        guard let targetID = sender.representedObject as? String else { return }
        model.selectTarget(MarketTarget.target(id: targetID))
    }

    @objc private func showTonghuashunCodeEditor() {
        let alert = NSAlert()
        alert.messageText = "输入同花顺代码"
        alert.informativeText = "输入 6 位数字，例如 883418（微盘股）。"
        let field = NSTextField(string: "883418")
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let target = MarketTarget.tonghuashun(code: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            let error = NSAlert()
            error.messageText = "代码格式不正确"
            error.informativeText = "请输入 6 位数字的同花顺代码。"
            error.runModal()
            return
        }
        model.selectTarget(target)
    }

    @objc private func toggleIndexPollingFromMenu(_ sender: NSMenuItem) {
        model.toggleIndexPolling()
    }

    @objc private func toggleMuteFromMenu(_ sender: NSMenuItem) {
        model.toggleMuted()
        statusMuteItem?.state = model.isMuted ? .on : .off
    }

    @objc private func toggleMarketPillFromMenu(_ sender: NSMenuItem) {
        model.toggleMarketPill()
        sender.state = model.showMarketPill ? .on : .off
        statusPillItem?.state = model.showMarketPill ? .on : .off
    }

    @objc private func showScaleEditorFromMenu() {
        if let scalePopover, scalePopover.isShown {
            scalePopover.close()
            return
        }
        let editor = ScaleEditorView(model: model) { [weak self] in
            self?.scalePopover?.close()
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 250, height: 160)
        popover.contentViewController = NSHostingController(rootView: editor)
        scalePopover = popover
        show(popover: popover)
    }

    @objc private func showSpeechScaleEditorFromMenu() {
        if let speechScalePopover, speechScalePopover.isShown {
            speechScalePopover.close()
            return
        }
        let editor = SpeechScaleEditorView(model: model) { [weak self] in
            self?.speechScalePopover?.close()
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 250, height: 160)
        popover.contentViewController = NSHostingController(rootView: editor)
        speechScalePopover = popover
        show(popover: popover)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        let origin = panel.frame.origin
        model.updatePanelPosition(x: origin.x, y: origin.y)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel()
        return false
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatusMenu(menu)
        scheduleSnapshotRefresh(for: menu)
    }

    private func observeLayoutChanges() {
        model.$petScalePercent
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizePanel(keepingCenter: true)
            }
            .store(in: &cancellables)
    }

    private func show(popover: NSPopover) {
        guard let host = contextHostingView else { return }
        let anchor = NSRect(x: host.bounds.midX - 1, y: host.bounds.midY - 1, width: 2, height: 2)
        popover.show(relativeTo: anchor, of: host, preferredEdge: .minY)
    }

    private func resizePanel(keepingCenter: Bool) {
        guard let panel else { return }
        let desired = FloatingLayout.size(for: model.petScalePercent)
        if panel.frame.size != desired {
            var frame = panel.frame
            if keepingCenter {
                let center = NSPoint(x: frame.midX, y: frame.midY)
                frame.size = desired
                frame.origin = NSPoint(x: center.x - desired.width / 2, y: center.y - desired.height / 2)
            } else {
                frame.size = desired
            }
            panel.setFrame(frame, display: true)
        }
        // Also clamp an unchanged-size panel on launch. A persisted origin
        // can be outside the current screen after a monitor/layout change.
        clampPanelToVisibleScreen()
    }

    private func clampPanelToVisibleScreen() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = panel.frame.origin
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - panel.frame.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - panel.frame.height))
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let shapeItem = NSMenuItem(title: "形态", action: nil, keyEquivalent: "")
        shapeItem.submenu = makeShapeSubmenu()
        menu.addItem(shapeItem)

        let targetItem = NSMenuItem(title: "指数", action: nil, keyEquivalent: "")
        targetItem.submenu = makeTargetSubmenu()
        menu.addItem(targetItem)

        let pill = NSMenuItem(title: "显示行情标签", action: #selector(toggleMarketPillFromMenu(_:)), keyEquivalent: "")
        pill.target = self
        pill.state = model.showMarketPill ? .on : .off
        menu.addItem(pill)

        menu.addItem(.separator())
        let scale = NSMenuItem(
            title: "调节宠物大小（\(Int(model.petScalePercent.rounded()))%）…",
            action: #selector(showScaleEditorFromMenu),
            keyEquivalent: ""
        )
        scale.target = self
        menu.addItem(scale)
        let speechScale = NSMenuItem(
            title: "调节台词字号（\(Int(model.speechTextScalePercent.rounded()))%）…",
            action: #selector(showSpeechScaleEditorFromMenu),
            keyEquivalent: ""
        )
        speechScale.target = self
        menu.addItem(speechScale)
        let mute = NSMenuItem(title: "静音", action: #selector(toggleMuteFromMenu(_:)), keyEquivalent: "")
        mute.target = self
        mute.state = model.isMuted ? .on : .off
        menu.addItem(mute)
        menu.addItem(.separator())

        let visibility = NSMenuItem(
            title: model.panelVisible ? "隐藏宠物" : "显示宠物",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        visibility.target = self
        menu.addItem(visibility)
        scheduleSnapshotRefresh(for: menu)
        return menu
    }

    private func makeShapeSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let values: [(String, String)] = [("自动", ControlMode.auto.rawValue)] + PetID.allCases.map { ($0.displayName, $0.rawValue) }
        for (title, value) in values {
            let item = NSMenuItem(title: title, action: #selector(selectShapeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = value == ControlMode.auto.rawValue
                ? (model.mode == .auto ? .on : .off)
                : (model.mode == .manual && model.activePet.rawValue == value ? .on : .off)
            submenu.addItem(item)
        }
        return submenu
    }

    private func makeTargetSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let groups: [[MarketTarget]] = [
            [.sse],
            [.csiAll, .thsAll],
            [.chinext, .star50],
            [.cni2000],
        ]
        for (groupIndex, group) in groups.enumerated() {
            if groupIndex > 0 { submenu.addItem(.separator()) }
            for target in group {
                let item = NSMenuItem(title: target.name, action: #selector(selectTargetFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = target.id
                let selected = !model.isIndexPollingEnabled && model.target.id == target.id
                item.state = selected ? .on : .off
                item.view = MarketMenuRowView(target: target, snapshot: model.snapshot(for: target), selected: selected)
                submenu.addItem(item)
            }
        }
        submenu.addItem(.separator())
        let microCap = MarketTarget.microCap
        let microCapItem = NSMenuItem(title: microCap.name, action: #selector(selectTargetFromMenu(_:)), keyEquivalent: "")
        microCapItem.target = self
        microCapItem.representedObject = microCap.id
        microCapItem.state = !model.isIndexPollingEnabled && model.target.id == microCap.id ? .on : .off
        microCapItem.view = MarketMenuRowView(target: microCap, snapshot: model.snapshot(for: microCap), selected: microCapItem.state == .on)
        submenu.addItem(microCapItem)
        if model.target.sourceKind == .tonghuashunPublic && !MarketTarget.all.contains(where: { $0.id == model.target.id }) && model.target.id != microCap.id {
            let custom = model.target
            let customItem = NSMenuItem(title: custom.name, action: #selector(selectTargetFromMenu(_:)), keyEquivalent: "")
            customItem.target = self
            customItem.representedObject = custom.id
            customItem.state = !model.isIndexPollingEnabled && model.target.id == custom.id ? .on : .off
            customItem.view = MarketMenuRowView(target: custom, snapshot: model.snapshot(for: custom), selected: customItem.state == .on)
            submenu.addItem(customItem)
        }
        let manual = NSMenuItem(title: "手动输入同花顺代码…", action: #selector(showTonghuashunCodeEditor), keyEquivalent: "")
        manual.target = self
        submenu.addItem(manual)
        submenu.addItem(.separator())
        let polling = NSMenuItem(
            title: "轮询指数（每 60 秒）",
            action: #selector(toggleIndexPollingFromMenu(_:)),
            keyEquivalent: ""
        )
        polling.target = self
        polling.toolTip = "开启后每 60 秒自动切换到下一个指数目标"
        polling.state = model.isIndexPollingEnabled ? .on : .off
        submenu.addItem(polling)
        return submenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        let icon = Bundle.main.url(forResource: "BrandMark", withExtension: "svg").flatMap { NSImage(contentsOf: $0) }
        icon?.isTemplate = true
        button.image = icon
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "牛来行情宠物"
        button.setAccessibilityLabel("牛来行情宠物")
        item.length = 24
        item.isVisible = true

        let menu = NSMenu()
        menu.delegate = self

        let summary = NSMenuItem(title: "指数 --", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        statusSummaryItem = summary

        let shapeItem = NSMenuItem(title: "形态", action: nil, keyEquivalent: "")
        shapeItem.submenu = makeShapeSubmenu()
        statusShapeItems = shapeItem.submenu?.items ?? []
        menu.addItem(shapeItem)

        let targetItem = NSMenuItem(title: "指数", action: nil, keyEquivalent: "")
        targetItem.submenu = makeTargetSubmenu()
        statusTargetItems = targetItem.submenu?.items.filter { $0.representedObject is String } ?? []
        statusPollingItem = targetItem.submenu?.items.first(where: { $0.action == #selector(toggleIndexPollingFromMenu(_:)) })
        menu.addItem(targetItem)

        let pillItem = NSMenuItem(title: "显示行情标签", action: #selector(toggleMarketPillFromMenu(_:)), keyEquivalent: "")
        pillItem.target = self
        menu.addItem(pillItem)
        statusPillItem = pillItem

        let scaleItem = NSMenuItem(title: "调节宠物大小…", action: #selector(showScaleEditorFromMenu), keyEquivalent: "")
        scaleItem.target = self
        menu.addItem(scaleItem)
        statusScaleItem = scaleItem

        let speechScaleItem = NSMenuItem(title: "调节台词字号…", action: #selector(showSpeechScaleEditorFromMenu), keyEquivalent: "")
        speechScaleItem.target = self
        menu.addItem(speechScaleItem)
        statusSpeechScaleItem = speechScaleItem

        let muteItem = NSMenuItem(title: "静音", action: #selector(toggleMuteFromMenu(_:)), keyEquivalent: "")
        muteItem.target = self
        menu.addItem(muteItem)
        statusMuteItem = muteItem

        menu.addItem(.separator())
        let visibility = NSMenuItem(title: "显示／隐藏宠物", action: #selector(togglePanel), keyEquivalent: "")
        visibility.target = self
        menu.addItem(visibility)
        menu.addItem(.separator())
        let exit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        exit.target = self
        menu.addItem(exit)

        item.menu = menu
        statusMenu = menu
        statusItem = item
        updateStatusMenu(menu)
    }

    private var statusMenu: NSMenu?

    private func updateStatusMenu(_ menu: NSMenu) {
        let summary = "\(model.target.name) \(MarketRules.signedPercent(model.quote?.percent)) · \(model.session.rawValue)"
        let tone = MarketTone.resolve(percent: model.quote?.percent, isStale: model.currentQuoteIsStale)
        statusSummaryItem?.attributedTitle = NSAttributedString(
            string: summary,
            attributes: [.foregroundColor: NSColor(hex: tone.colorHex)]
        )
        for item in statusShapeItems {
            guard let value = item.representedObject as? String else { continue }
            item.state = value == ControlMode.auto.rawValue
                ? (model.mode == .auto ? .on : .off)
                : (model.mode == .manual && model.activePet.rawValue == value ? .on : .off)
        }
        for item in statusTargetItems {
            guard let targetID = item.representedObject as? String else { continue }
            let selected = !model.isIndexPollingEnabled && model.target.id == targetID
            item.state = selected ? .on : .off
            let target = MarketTarget.target(id: targetID)
            if let row = item.view as? MarketMenuRowView {
                row.update(snapshot: model.snapshot(for: target), selected: selected)
            }
        }
        statusPollingItem?.state = model.isIndexPollingEnabled ? .on : .off
        statusScaleItem?.title = "调节宠物大小（\(Int(model.petScalePercent.rounded()))%）…"
        statusSpeechScaleItem?.title = "调节台词字号（\(Int(model.speechTextScalePercent.rounded()))%）…"
        statusMuteItem?.state = model.isMuted ? .on : .off
        statusPillItem?.state = model.showMarketPill ? .on : .off
        _ = menu
    }

    private func scheduleSnapshotRefresh(for menu: NSMenu) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.model.refreshSnapshotsForMenu()
            self.updateStatusMenu(menu)
            for item in menu.items {
                if let submenu = item.submenu { self.updateTargetRows(in: submenu) }
            }
        }
    }

    private func updateTargetRows(in menu: NSMenu) {
        for item in menu.items {
            guard let targetID = item.representedObject as? String,
                  let row = item.view as? MarketMenuRowView else { continue }
            let target = MarketTarget.target(id: targetID)
            row.update(
                snapshot: model.snapshot(for: target),
                selected: !model.isIndexPollingEnabled && model.target.id == targetID
            )
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }
}
