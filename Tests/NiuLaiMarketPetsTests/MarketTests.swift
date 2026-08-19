import Foundation
@testable import NiuLaiMarketPets

@main
struct MarketTestRunner {
    static func main() async {
        run("threshold boundaries") {
            expect(MarketRules.bucket(for: -0.01) == .muamua)
            expect(MarketRules.bucket(for: 0) == .niulai)
            expect(MarketRules.bucket(for: 1) == .niulai)
            expect(MarketRules.bucket(for: 1.01) == .baola)
        }
        run("percent calculation") {
            expect(abs(Quote.percent(lastPrice: 3012, previousClose: 3000) - 0.4) < 0.0001)
        }
        run("market target catalog and migration") {
            expect(MarketTarget.default.id == "ths-all")
            expect(MarketTarget.all.count == 6)
            expect(MarketTarget.target(id: "star50") == .star50)
            expect(MarketTarget.target(id: "unknown").id == MarketTarget.default.id)
            expect(MarketTarget.nextPollingTarget(after: "sse") == .csiAll)
            expect(MarketTarget.nextPollingTarget(after: "cni-2000") == .sse)

            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = StateStore(rootURL: root)
            let legacyState = """
            {"activePetID":"niulai","lastMarketPercent":0.19,"lastProvider":"backup","mode":"auto","panelVisible":true}
            """
            try! Data(legacyState.utf8).write(to: store.stateURL)
            expect(store.load().targetID == MarketTarget.default.id)
            var saved = store.load()
            saved.targetID = MarketTarget.csiAll.id
            try! store.save(saved)
            expect(store.load().targetID == "csi-all")
        }
        run("Tonghuashun 883421 fixture parser") {
            let fixture = """
            <div class="board-hq">
              <span class="board-xj arr-rise" >1354.42</span>
            </div>
            <div class="board-infos">
              <dl><dt>今开</dt><dd>1342.06</dd></dl>
              <dl><dt>昨收</dt><dd>1347.05</dd></dl>
              <dl><dt>最低</dt><dd>-</dd></dl>
            </div>
            """
            expect(TonghuashunHTMLParser.lastPrice(in: fixture) == 1354.42)
            expect(TonghuashunHTMLParser.previousClose(in: fixture) == 1347.05)
            expect(Quote.percent(lastPrice: 1354.42, previousClose: 1347.05) > 0.54)
        }
        run("speech cadence and click burst") {
            let start = Date(timeIntervalSinceReferenceDate: 105)
            expect(SpeechPlanner.defaultCue(for: .niulai, at: start)?.text == "牛来")
            expect(SpeechPlanner.defaultCue(for: .niulai, at: start.addingTimeInterval(SpeechPlanner.defaultVisibleDuration + 0.01)) == nil)
            expect(SpeechPlanner.burstCue(for: .baola, elapsed: 0)?.text == "豹拉 All in")
            expect(SpeechPlanner.burstCue(for: .baola, elapsed: SpeechPlanner.burstStep + 0.01)?.text == "豹拉起飞")
            expect(SpeechPlanner.burstCue(for: .muamua, elapsed: SpeechPlanner.burstDuration + 0.01) == nil)
            let burst = SpeechPlanner.cue(for: .muamua, at: start, burstStartedAt: start)
            expect(burst?.isBurst == true)
        }
        run("speech bubbles and copy") {
            let start = Date(timeIntervalSinceReferenceDate: 105.1)
            let idle = SpeechPlanner.bubbles(for: .muamua, at: start, burstStartedAt: nil)
            expect(idle.count == 1)
            expect(idle[0].text != "妈妈别走")
            expect(idle[0].fontName.isEmpty == false)
            let burst = SpeechPlanner.burstBubbles(for: .muamua, startedAt: start, at: start.addingTimeInterval(0.7), textScale: 1.2)
            expect(burst.count >= 2)
            expect(burst.contains(where: { $0.text == "妈妈救我！" }))
            expect(Set(burst.map(\.originX)).count >= 2)
            expect(Set(burst.map(\.text)).count == burst.count)
            let fullBurst = SpeechPlanner.burstBubbles(for: .muamua, startedAt: start, at: start.addingTimeInterval(0.95))
            expect(fullBurst.count == 3)
            expect(burst.allSatisfy { $0.fontSize >= 24 * 1.19 })
        }
        run("debounce and cooldown") {
            var engine = MarketStateEngine(activePet: .niulai, hasHistory: true)
            let start = Date(timeIntervalSince1970: 1000)
            expect(engine.accept(percent: 1.01, at: start, tradingAllowed: true, isStale: false) == nil)
            expect(engine.accept(percent: 1.01, at: start.addingTimeInterval(19), tradingAllowed: true, isStale: false) == nil)
            expect(engine.accept(percent: 1.01, at: start.addingTimeInterval(20), tradingAllowed: true, isStale: false) == .baola)
            expect(engine.accept(percent: -0.1, at: start.addingTimeInterval(21), tradingAllowed: true, isStale: false) == nil)
            expect(engine.accept(percent: -0.1, at: start.addingTimeInterval(141), tradingAllowed: true, isStale: false) == nil)
            expect(engine.accept(percent: -0.1, at: start.addingTimeInterval(161), tradingAllowed: true, isStale: false) == .muamua)
        }
        run("first sample and invalid reset") {
            var engine = MarketStateEngine(activePet: .niulai, hasHistory: false)
            expect(engine.accept(percent: -0.01, at: Date(), tradingAllowed: true, isStale: false) == .muamua)
            expect(engine.accept(percent: .nan, at: Date(), tradingAllowed: true, isStale: false) == nil)
            expect(engine.accept(percent: 1.01, at: Date(), tradingAllowed: false, isStale: false) == nil)
        }
        run("TOML preserves sections and comments") {
            let editor = ConfigEditor(configURL: URL(fileURLWithPath: "/tmp/does-not-exist"))
            let original = "# keep\n[other]\nvalue = 1\n\n[desktop]\n# note\nselected-avatar-id = \"seedy\"\n\n[tail]\nkeep = true\n"
            let changed = editor.replacingSelectedAvatar(in: original, with: "custom:niulai")
            expect(changed.contains("selected-avatar-id = \"custom:niulai\""))
            expect(changed.contains("[other]\nvalue = 1"))
            expect(changed.contains("[tail]\nkeep = true"))
            expect(editor.selectedAvatar(in: changed) == "custom:niulai")
        }
        run("TOML adds missing desktop") {
            let editor = ConfigEditor(configURL: URL(fileURLWithPath: "/tmp/does-not-exist"))
            let added = editor.replacingSelectedAvatar(in: "[other]\nvalue = 1\n", with: "custom:baola")
            expect(added.contains("[desktop]\nselected-avatar-id = \"custom:baola\""))
        }
        run("corrupt state recovery") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = StateStore(rootURL: root)
            try! Data("not-json".utf8).write(to: store.stateURL)
            expect(store.load() == PersistedState())
        }
        run("pet scale percentage compatibility") {
            expect(PetScaleRange.clamped(50) == 60)
            expect(PetScaleRange.clamped(100) == 100)
            expect(PetScaleRange.clamped(180) == 160)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = StateStore(rootURL: root)
            let legacyState = """
            {"activePetID":"niulai","lastMarketPercent":0.19,"lastProvider":"backup","mode":"auto","panelVisible":true,"petScale":"large"}
            """
            try! Data(legacyState.utf8).write(to: store.stateURL)
            expect(store.load().petScalePercent == 118)
            var saved = store.load()
            saved.petScalePercent = 132.5
            try! store.save(saved)
            expect(store.load().petScalePercent == 132.5)
            expect(String(data: try! Data(contentsOf: store.stateURL), encoding: .utf8)!.contains("petScalePercent"))
        }
        run("speech scale and polling state compatibility") {
            let legacy = PersistedState()
            expect(legacy.speechTextScalePercent == SpeechTextScaleRange.defaultPercent)
            expect(legacy.indexPollingEnabled == false)
            expect(legacy.isMuted == false)
            let migrated = PersistedState(speechTextScalePercent: 140, indexPollingEnabled: true)
            expect(migrated.speechTextScalePercent == 140)
            expect(migrated.indexPollingEnabled)
            let data = try! JSONEncoder().encode(migrated)
            let decoded = try! JSONDecoder().decode(PersistedState.self, from: data)
            expect(decoded == migrated)
            let clamped = PersistedState(speechTextScalePercent: 200)
            expect(clamped.speechTextScalePercent == SpeechTextScaleRange.maxPercent)
            expect(ControllerModel.indexPollingInterval == 60)
        }
        run("click audio catalog and mute persistence") {
            expect(ClickAudioCatalog.names(for: .niulai) == ["niulai"])
            expect(ClickAudioCatalog.names(for: .baola) == ["baola"])
            expect(Set(ClickAudioCatalog.names(for: .muamua)) == ["muamua-mama-long", "muamua-mama-rescue"])
            let muted = PersistedState(isMuted: true)
            let data = try! JSONEncoder().encode(muted)
            let decoded = try! JSONDecoder().decode(PersistedState.self, from: data)
            expect(decoded.isMuted)
        }
        await MainActor.run {
            run("polling and manual target selection are mutually exclusive") {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let model = ControllerModel(stateStore: StateStore(rootURL: root))
                model.setIndexPollingEnabled(true)
                expect(model.isIndexPollingEnabled)
                model.selectTarget(.sse)
                expect(model.target == .sse)
                expect(model.isIndexPollingEnabled == false)
                model.setIndexPollingEnabled(true)
                model.selectTarget(.sse)
                expect(model.isIndexPollingEnabled == false)
            }
        }
        run("market sessions") {
            let calendar = MarketRules.shanghaiCalendar
            func date(_ hour: Int, _ minute: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: hour, minute: minute))! }
            expect(MarketRules.session(for: date(9, 20)) == .preOpen)
            expect(MarketRules.session(for: date(10, 0)) == .trading)
            expect(MarketRules.session(for: date(12, 0)) == .lunch)
            expect(MarketRules.session(for: date(16, 0)) == .closed)
        }
        let backupQuote = Quote(lastPrice: 3030, previousClose: 3000, quoteTimestamp: Date(), provider: "backup")
        let fallback = QuoteService(
            primary: StubQuoteProvider(name: "primary", quote: nil, shouldThrow: true),
            backup: StubQuoteProvider(name: "backup", quote: backupQuote, shouldThrow: false)
        )
        let fallbackResult = await fallback.fetch()
        expect(fallbackResult.quote?.provider == "backup")
        expect(fallbackResult.errors.count == 1)
        let unavailable = QuoteService(
            primary: StubQuoteProvider(name: "primary", quote: nil, shouldThrow: true),
            backup: StubQuoteProvider(name: "backup", quote: nil, shouldThrow: true)
        )
        let unavailableResult = await unavailable.fetch()
        expect(unavailableResult.quote == nil)
        expect(unavailableResult.errors.count == 2)
        print("PASS: primary backup and dual failure")
        run("manual priority seam") {
            var engine = MarketStateEngine(activePet: .muamua, hasHistory: true)
            engine.resetForManual(pet: .baola)
            expect(engine.accept(percent: -2, at: Date(), tradingAllowed: true, isStale: false) == nil)
            expect(engine.activePet == .baola)
        }
        run("missing Codex setup degrades quietly") {
            let setupConfig = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/codex-app/config.json")
            if !FileManager.default.fileExists(atPath: setupConfig.path) {
                expect(DeepLinkReloader().reload())
            }
        }
        print("swift-test-harness: PASS (15 groups)")
    }

    static func run(_ name: String, _ body: () -> Void) {
        body()
        print("PASS: \(name)")
    }

    static func expect(_ condition: @autoclosure () -> Bool) {
        precondition(condition(), "assertion failed")
    }
}

private struct StubQuoteProvider: QuoteProviding {
    let name: String
    let quote: Quote?
    let shouldThrow: Bool

    func fetch() async throws -> Quote {
        if shouldThrow { throw ProviderError.invalidPayload }
        guard let quote else { throw ProviderError.invalidPayload }
        return quote
    }
}
