import AppKit
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = ControllerModel()
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        model.start()
        requestNotifications()
        setupStatusItem()
        showPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func showPanel() {
        if panel == nil {
            let frame = NSRect(x: 0, y: 0, width: 320, height: 180)
            let created = FloatingPanel(frame: frame)
            created.contentView = NSHostingView(rootView: ControllerView(model: model, onHide: { [weak self] in self?.hidePanel() }))
            created.delegate = self
            panel = created
        }
        guard let panel else { return }
        if let x = model.panelX, let y = model.panelY {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - 332, y: visible.minY + 20))
        }
        panel.orderFrontRegardless()
        model.panelVisible = true
    }

    func hidePanel() {
        guard let panel else { return }
        let origin = panel.frame.origin
        model.updatePanelPosition(x: origin.x, y: origin.y)
        model.panelVisible = false
        panel.orderOut(nil)
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true { hidePanel() } else { showPanel() }
    }

    @objc private func restoreAuto() { model.selectAuto() }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        let origin = panel.frame.origin
        model.updatePanelPosition(x: origin.x, y: origin.y)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel()
        return false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "牛来行情宠物")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示／隐藏面板", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "恢复自动", action: #selector(restoreAuto), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }
}
