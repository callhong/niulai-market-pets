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
    @Published public private(set) var isWatchlistPollingEnabled = false
    @Published public private(set) var watchlistCodes: [String] = []
    @Published public private(set) var isMuted = false
    @Published public private(set) var showMarketPill = true
    @Published public private(set) var marketSnapshots: [String: MarketSnapshot] = [:]
    @Published public private(set) var speechBurstStartedAt: Date?

    public let stateStore: StateStore
    private var quoteService: QuoteService
    private var engine: MarketStateEngine
    private var pollingTask: Task<Void, Never>?
    private var indexPollingTask: Task<Void, Never>?
    private var isStarted = false
    private let clickAudioPlayer: ClickAudioPlayer
    private var notificationPolicy = NotificationPolicy()
    private var isFirstValidQuote = true
    private var suppressEffectsForTargetChange = false

    public static let indexPollingInterval: TimeInterval = 60

    public var customTargets: [MarketTarget] {
        watchlistCodes.compactMap { MarketTarget.tonghuashun(code: $0) }
    }

    public var displayTargetName: String {
        quote?.name ?? target.name
    }

    public init(
        quoteService: QuoteService = QuoteService(target: .default),
        stateStore: StateStore = StateStore(),
        clickAudioPlayer: ClickAudioPlayer? = nil
    ) {
        self.quoteService = quoteService
        self.stateStore = stateStore
        self.engine = MarketStateEngine()
        self.clickAudioPlayer = clickAudioPlayer ?? ClickAudioPlayer()
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
        watchlistCodes = state.watchlistCodes
        if target.isCustomCode && !watchlistCodes.contains(target.symbol) {
            watchlistCodes.append(target.symbol)
        }
        // A persisted percent is shown through state/diagnostics until a fresh Quote arrives;
        // never fabricate a price pair that could be mistaken for live data.
        quote = nil
        panelVisible = state.panelVisible
        panelX = state.panelX
        panelY = state.panelY
        petScalePercent = state.petScalePercent
        speechTextScalePercent = state.speechTextScalePercent
        isIndexPollingEnabled = state.indexPollingEnabled
        isWatchlistPollingEnabled = !isIndexPollingEnabled && state.watchlistPollingEnabled && !customTargets.isEmpty
        isMuted = state.isMuted
        showMarketPill = state.showMarketPill
        speechBurstStartedAt = nil
        marketSnapshots = [:]
        notificationPolicy.reset()
        isFirstValidQuote = true
        suppressEffectsForTargetChange = false
        engine = MarketStateEngine(activePet: activePet, hasHistory: state.lastMarketPercent != nil)
        if mode == .manual, let manual = state.manualPetID { activePet = manual; engine.resetForManual(pet: manual) }
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
        mode = .manual
        engine.resetForManual(pet: pet)
        activePet = pet
        lastError = nil
        notificationPolicy.reset()
        triggerSpeechBurst()
        playClickAudio(for: pet)
        saveState()
    }

    public func selectTarget(_ newTarget: MarketTarget) {
        selectTarget(newTarget, disablesPolling: true)
    }

    private func selectTarget(_ newTarget: MarketTarget, disablesPolling: Bool) {
        if disablesPolling {
            setIndexPollingEnabled(false)
            setWatchlistPollingEnabled(false)
        }
        addToWatchlistIfNeeded(newTarget)
        guard newTarget != target else { return }
        target = newTarget
        quoteService = QuoteService(target: newTarget)
        quote = nil
        isOnline = false
        session = .offline
        lastError = nil
        notificationPolicy.reset()
        isFirstValidQuote = true
        suppressEffectsForTargetChange = true
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
        if let quote, !currentQuoteIsStale, let next = MarketRules.bucket(for: quote.percent), next != activePet {
            activePet = next
            triggerSpeechBurst()
            playClickAudio(for: next)
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
            isWatchlistPollingEnabled = false
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

    public func setWatchlistPollingEnabled(_ enabled: Bool) {
        isWatchlistPollingEnabled = enabled && !customTargets.isEmpty
        if isWatchlistPollingEnabled {
            isIndexPollingEnabled = false
            startIndexPollingTaskIfNeeded()
        } else if !isIndexPollingEnabled {
            indexPollingTask?.cancel()
            indexPollingTask = nil
        }
        saveState()
    }

    public func toggleWatchlistPolling() {
        setWatchlistPollingEnabled(!isWatchlistPollingEnabled)
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        saveState()
    }

    public func toggleMuted() {
        setMuted(!isMuted)
    }

    public func setShowMarketPill(_ visible: Bool) {
        showMarketPill = visible
        saveState()
    }

    public func toggleMarketPill() {
        setShowMarketPill(!showMarketPill)
    }

    @discardableResult
    public func addWatchlistCode(_ code: String) -> MarketTarget? {
        guard let newTarget = MarketTarget.tonghuashun(code: code.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        addToWatchlistIfNeeded(newTarget)
        selectTarget(newTarget)
        return newTarget
    }

    public func removeWatchlistCode(_ code: String) {
        watchlistCodes.removeAll { $0 == code }
        if watchlistCodes.isEmpty { isWatchlistPollingEnabled = false }
        if target.symbol == code {
            selectTarget(.default)
        } else {
            saveState()
        }
    }

    public var currentQuoteIsStale: Bool {
        marketSnapshots[target.id]?.isStale(at: Date()) ?? quote?.isStale ?? true
    }

    public func snapshot(for target: MarketTarget, at date: Date = Date()) -> MarketSnapshot {
        marketSnapshots[target.id] ?? MarketSnapshot(targetID: target.id)
    }

    public func displayName(for target: MarketTarget) -> String {
        snapshot(for: target).quote?.name ?? (target.id == self.target.id ? displayTargetName : target.name)
    }

    public func playClickAudio(for pet: PetID? = nil) {
        guard MarketSoundPolicy.shouldPlay(event: .click, isMuted: isMuted) else { return }
        clickAudioPlayer.play(for: pet ?? activePet)
    }

    public func triggerSpeechBurst() {
        speechBurstStartedAt = Date()
    }

    public func refresh() async {
        let targetID = target.id
        let result = await quoteService.fetch()
        guard target.id == targetID else { return }
        applyFetch(result, for: target, at: Date(), isTargetRotation: suppressEffectsForTargetChange)
        suppressEffectsForTargetChange = false
    }

    /// Refreshes missing or older-than-one-minute snapshots concurrently after
    /// a menu opens. Menu construction remains synchronous and uses the cached
    /// values while these requests are in flight.
    public func refreshSnapshotsForMenu(at date: Date = Date()) async {
        var catalog = MarketTarget.all + [MarketTarget.microCap] + customTargets
        if !catalog.contains(where: { $0.id == target.id }) {
            catalog.append(target)
        }
        let targets = catalog.filter { target in
            snapshot(for: target, at: date).isStale(at: date)
        }
        guard !targets.isEmpty else { return }
        await withTaskGroup(of: (MarketTarget, QuoteFetchResult).self) { group in
            for target in targets {
                group.addTask {
                    (target, await QuoteService(target: target).fetch())
                }
            }
            for await (target, result) in group {
                applyFetch(
                    result,
                    for: target,
                    at: Date(),
                    isTargetRotation: target.id == self.target.id ? self.suppressEffectsForTargetChange : true
                )
                if target.id == self.target.id {
                    self.suppressEffectsForTargetChange = false
                }
            }
        }
    }

    /// Test seam: applies one quote without network access and returns the switched pet, if any.
    @discardableResult
    public func applyQuoteForTesting(percent: Double, at date: Date, tradingAllowed: Bool = true, isStale: Bool = false) -> PetID? {
        guard mode == .auto else { return nil }
        guard let next = engine.accept(percent: percent, at: date, tradingAllowed: tradingAllowed, isStale: isStale) else { return nil }
        activePet = next
        return next
    }

    private func applySwitch(
        _ pet: PetID,
        previousPercent: Double?,
        currentPercent: Double,
        isInitialSample: Bool,
        isTargetRotation: Bool,
        isStale: Bool,
        allowsNotification: Bool
    ) {
        guard pet != activePet else { return }
        activePet = pet
        lastError = nil
        let soundEvent: MarketSoundEvent = isTargetRotation ? .targetRotation : .automaticShapeSwitch
        if MarketSoundPolicy.shouldPlay(event: soundEvent, isMuted: isMuted) {
            triggerSpeechBurst()
            playClickAudio(for: pet)
        }
        if allowsNotification && notificationPolicy.shouldNotify(
            previousPercent: previousPercent,
            currentPercent: currentPercent,
            switchedTo: pet,
            mode: mode,
            isInitialSample: isInitialSample,
            isTargetRotation: isTargetRotation,
            isStale: isStale
        ) {
            sendNotification(for: pet, quote: quote)
        }
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
            watchlistCodes: watchlistCodes,
            watchlistPollingEnabled: isWatchlistPollingEnabled,
            isMuted: isMuted,
            showMarketPill: showMarketPill
        )
        try? stateStore.save(state)
    }

    private func startIndexPollingTaskIfNeeded() {
        indexPollingTask?.cancel()
        guard isStarted, isIndexPollingEnabled || isWatchlistPollingEnabled else { return }
        indexPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && (self.isIndexPollingEnabled || self.isWatchlistPollingEnabled) {
                try? await Task.sleep(nanoseconds: UInt64(Self.indexPollingInterval * 1_000_000_000))
                guard !Task.isCancelled, self.isIndexPollingEnabled || self.isWatchlistPollingEnabled else { return }
                self.advancePolledTarget()
            }
        }
    }

    private func advancePolledTarget() {
        if isIndexPollingEnabled {
            selectTarget(MarketTarget.nextPollingTarget(after: target.id), disablesPolling: false)
            return
        }
        guard isWatchlistPollingEnabled, !customTargets.isEmpty else { return }
        let targets = customTargets
        let currentIndex = targets.firstIndex(where: { $0.id == target.id }) ?? -1
        let next = targets[(currentIndex + 1) % targets.count]
        selectTarget(next, disablesPolling: false)
    }

    private func sendNotification(for pet: PetID, quote: Quote?) {
        let content = UNMutableNotificationContent()
        content.title = NotificationPolicy.title(for: pet)
        content.body = NotificationPolicy.body(for: pet, target: target, quote: quote)
        content.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "niulai-\(pet.rawValue)", content: content, trigger: nil))
    }

    private func applyFetch(
        _ result: QuoteFetchResult,
        for target: MarketTarget,
        at date: Date,
        isTargetRotation: Bool
    ) {
        let errorText = result.errors.isEmpty ? nil : result.errors.joined(separator: " | ")
        let validQuote = result.quote.flatMap { quote in
            quote.symbol == target.symbol && quote.isUsable ? quote : nil
        }
        var snapshot = marketSnapshots[target.id] ?? MarketSnapshot(targetID: target.id)
        if let validQuote {
            snapshot.quote = validQuote
            snapshot.fetchedAt = date
            snapshot.lastError = errorText
            marketSnapshots[target.id] = snapshot
        } else {
            snapshot.lastError = errorText ?? "Quote payload did not match the selected target"
            marketSnapshots[target.id] = snapshot
        }

        guard target.id == self.target.id else { return }
        lastRefreshAt = date
        let previousPercent = quote?.percent
        if let validQuote {
            quote = validQuote
            let stale = snapshot.isStale(at: date)
            isOnline = !stale
            lastError = snapshot.lastError
            let sessionNow = MarketRules.session(for: date)
            session = stale ? .stale : sessionNow
            if mode == .auto, !stale,
               let next = engine.accept(percent: validQuote.percent, at: date, tradingAllowed: true, isStale: false) {
                applySwitch(
                    next,
                    previousPercent: previousPercent,
                    currentPercent: validQuote.percent,
                    isInitialSample: isFirstValidQuote,
                    isTargetRotation: isTargetRotation,
                    isStale: stale,
                    allowsNotification: sessionNow == .trading
                )
            }
            if stale { engine.clearPendingCandidate() }
            isFirstValidQuote = false
        } else {
            isOnline = false
            session = snapshot.quote == nil ? .offline : .stale
            lastError = snapshot.lastError
            engine.clearPendingCandidate()
        }
        saveState()
    }

    private func addToWatchlistIfNeeded(_ target: MarketTarget) {
        guard target.isCustomCode, !watchlistCodes.contains(target.symbol) else { return }
        watchlistCodes.append(target.symbol)
        if watchlistCodes.count > 100 { watchlistCodes = Array(watchlistCodes.prefix(100)) }
    }
}
