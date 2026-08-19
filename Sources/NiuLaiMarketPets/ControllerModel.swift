import Combine
import Foundation
import UserNotifications

@MainActor
public final class ControllerModel: ObservableObject {
    @Published public private(set) var mode: ControlMode = .auto
    @Published public private(set) var activePet: PetID = .niulai
    @Published public private(set) var target: MarketTarget = .default
    @Published public private(set) var quote: Quote?
    @Published public private(set) var session: MarketSession = .offline
    @Published public private(set) var lastError: String?
    @Published public private(set) var isOnline = false
    @Published public private(set) var lastRefreshAt: Date?
    @Published public var panelVisible = true
    @Published public var panelX: Double?
    @Published public var panelY: Double?
    @Published public private(set) var petScalePercent: Double = PetScaleRange.defaultPercent
    @Published public private(set) var speechTextScalePercent: Double = SpeechTextScaleRange.defaultPercent
    @Published public private(set) var isIndexPollingEnabled = false
    @Published public private(set) var isMuted = false

    public let stateStore: StateStore
    private var quoteService: QuoteService
    private let petSwitcher: PetSwitcher
    private var engine: MarketStateEngine
    private var pollingTask: Task<Void, Never>?
    private var indexPollingTask: Task<Void, Never>?
    private var isStarted = false
    private let clickAudioPlayer: ClickAudioPlayer

    public static let indexPollingInterval: TimeInterval = 60

    public init(
        quoteService: QuoteService = QuoteService(target: .default),
        petSwitcher: PetSwitcher = PetSwitcher(),
        stateStore: StateStore = StateStore(),
        clickAudioPlayer: ClickAudioPlayer = ClickAudioPlayer()
    ) {
        self.quoteService = quoteService
        self.petSwitcher = petSwitcher
        self.stateStore = stateStore
        self.engine = MarketStateEngine()
        self.clickAudioPlayer = clickAudioPlayer
    }

    deinit {
        pollingTask?.cancel()
        indexPollingTask?.cancel()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        let state = stateStore.load()
        target = MarketTarget.target(id: state.targetID)
        quoteService = QuoteService(target: target)
        mode = state.mode
        activePet = state.activePetID
        // A persisted percent is shown through state/diagnostics until a fresh Quote arrives;
        // never fabricate a price pair that could be mistaken for live data.
        quote = nil
        panelVisible = state.panelVisible
        panelX = state.panelX
        panelY = state.panelY
        petScalePercent = state.petScalePercent
        speechTextScalePercent = state.speechTextScalePercent
        isIndexPollingEnabled = state.indexPollingEnabled
        isMuted = state.isMuted
        engine = MarketStateEngine(activePet: activePet, hasHistory: state.lastMarketPercent != nil)
        if mode == .manual, let manual = state.manualPetID { activePet = manual; engine.resetForManual(pet: manual) }
        synchronizeCodexPet()
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                let seconds: UInt64 = self.session == .trading ? 60 : 300
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
        startIndexPollingTaskIfNeeded()
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        indexPollingTask?.cancel()
        indexPollingTask = nil
        isStarted = false
    }

    public func selectManual(_ pet: PetID) {
        let previous = activePet
        let previousMode = mode
        mode = .manual
        engine.resetForManual(pet: pet)
        do {
            _ = try petSwitcher.switchTo(pet, current: previous)
            activePet = pet
            lastError = nil
            playClickAudio(for: pet)
        } catch {
            mode = previousMode
            activePet = previous
            engine = MarketStateEngine(activePet: previous, hasHistory: quote?.percent.isFinite == true)
            lastError = error.localizedDescription
        }
        saveState()
    }

    public func selectTarget(_ newTarget: MarketTarget) {
        selectTarget(newTarget, disablesPolling: true)
    }

    private func selectTarget(_ newTarget: MarketTarget, disablesPolling: Bool) {
        if disablesPolling, isIndexPollingEnabled {
            setIndexPollingEnabled(false)
        }
        guard newTarget != target else { return }
        target = newTarget
        quoteService = QuoteService(target: newTarget)
        quote = nil
        isOnline = false
        session = .offline
        lastError = nil
        engine = MarketStateEngine(activePet: activePet, hasHistory: false)
        saveState()
        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    public func selectAuto() {
        mode = .auto
        engine = MarketStateEngine(activePet: activePet, hasHistory: false)
        // An explicit request to resume automatic mode uses the last fresh
        // quote immediately, including outside trading hours. Passive polling
        // still obeys the trading-session gate in refresh().
        if let quote, !quote.isStale, let next = MarketRules.bucket(for: quote.percent), next != activePet {
            applySwitch(next, reason: "恢复自动")
        }
        saveState()
    }

    public func togglePanelVisibility() {
        setPanelVisible(!panelVisible)
    }

    public func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        saveState()
    }

    public func updatePanelPosition(x: Double, y: Double) {
        panelX = x
        panelY = y
        saveState()
    }

    public func setPetScalePercent(_ percent: Double) {
        petScalePercent = PetScaleRange.clamped(percent)
        saveState()
    }

    public func setSpeechTextScalePercent(_ percent: Double) {
        speechTextScalePercent = SpeechTextScaleRange.clamped(percent)
        saveState()
    }

    public func setIndexPollingEnabled(_ enabled: Bool) {
        isIndexPollingEnabled = enabled
        if enabled {
            startIndexPollingTaskIfNeeded()
        } else {
            indexPollingTask?.cancel()
            indexPollingTask = nil
        }
        saveState()
    }

    public func toggleIndexPolling() {
        setIndexPollingEnabled(!isIndexPollingEnabled)
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        saveState()
    }

    public func toggleMuted() {
        setMuted(!isMuted)
    }

    public func playClickAudio(for pet: PetID? = nil) {
        guard !isMuted else { return }
        clickAudioPlayer.play(for: pet ?? activePet)
    }

    private func synchronizeCodexPet() {
        do {
            _ = try petSwitcher.switchTo(activePet, current: nil)
        } catch {
            lastError = "Codex 宠物同步失败：\(error.localizedDescription)"
        }
    }

    public func refresh() async {
        let targetID = target.id
        let result = await quoteService.fetch()
        guard target.id == targetID else { return }
        lastRefreshAt = Date()
        if let quote = result.quote {
            self.quote = quote
            isOnline = true
            lastError = result.errors.isEmpty ? nil : result.errors.joined(separator: " | ")
            let now = Date()
            let sessionNow = MarketRules.session(for: now)
            let stale = quote.isStale || now.timeIntervalSince(quote.quoteTimestamp) > 300
            session = stale ? .stale : sessionNow
            if mode == .auto, sessionNow.allowsAutomaticSwitch, !stale,
               let next = engine.accept(percent: quote.percent, at: now, tradingAllowed: true, isStale: false) {
                applySwitch(next, reason: "行情自动")
            }
        } else {
            isOnline = false
            session = .offline
            lastError = result.errors.joined(separator: " | ")
            engine.clearPendingCandidate()
        }
        saveState()
    }

    /// Test seam: applies one quote without network access and returns the switched pet, if any.
    @discardableResult
    public func applyQuoteForTesting(percent: Double, at date: Date, tradingAllowed: Bool = true, isStale: Bool = false) -> PetID? {
        guard mode == .auto else { return nil }
        guard let next = engine.accept(percent: percent, at: date, tradingAllowed: tradingAllowed, isStale: isStale) else { return nil }
        activePet = next
        return next
    }

    private func applySwitch(_ pet: PetID, reason: String) {
        let previous = activePet
        do {
            _ = try petSwitcher.switchTo(pet, current: previous)
            activePet = pet
            lastError = nil
            playClickAudio(for: pet)
            sendNotification(for: pet)
        } catch { lastError = "\(reason)：\(error.localizedDescription)" }
    }

    private func saveState() {
        let state = PersistedState(
            targetID: target.id,
            mode: mode,
            manualPetID: mode == .manual ? activePet : nil,
            activePetID: activePet,
            lastMarketPercent: quote?.percent,
            lastQuoteAt: quote?.quoteTimestamp,
            lastProvider: quote?.provider,
            panelVisible: panelVisible,
            panelX: panelX,
            panelY: panelY,
            petScalePercent: petScalePercent,
            speechTextScalePercent: speechTextScalePercent,
            indexPollingEnabled: isIndexPollingEnabled,
            isMuted: isMuted
        )
        try? stateStore.save(state)
    }

    private func startIndexPollingTaskIfNeeded() {
        indexPollingTask?.cancel()
        guard isStarted, isIndexPollingEnabled else { return }
        indexPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isIndexPollingEnabled {
                try? await Task.sleep(nanoseconds: UInt64(Self.indexPollingInterval * 1_000_000_000))
                guard !Task.isCancelled, self.isIndexPollingEnabled else { return }
                self.advancePolledTarget()
            }
        }
    }

    private func advancePolledTarget() {
        selectTarget(MarketTarget.nextPollingTarget(after: target.id), disablesPolling: false)
    }

    private func sendNotification(for pet: PetID) {
        let content = UNMutableNotificationContent()
        content.title = pet == .muamua ? "妈妈——" : pet == .baola ? "豹拉！" : "牛来了"
        content.body = "上证指数 \(MarketRules.signedPercent(quote?.percent))"
        content.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "niulai-\(pet.rawValue)", content: content, trigger: nil))
    }
}
