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
            expect(MarketTone.resolve(percent: -0.0001) == .negative)
            expect(MarketTone.resolve(percent: 0) == .neutral)
            expect(MarketTone.resolve(percent: 0.0001) == .positive)
            expect(MarketTone.resolve(percent: nil) == .unavailable)
            expect(MarketRules.signedPercent(-0.004) == "+0.00%")
            expect(!MarketRules.signedPercent(-0.004).contains("-0.00"))
        }
        run("shared cross-platform model cases") {
            let source = URL(fileURLWithPath: #filePath)
            let fixtureURL = source
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("platforms/shared/market-model-cases.json")
            let data = try! Data(contentsOf: fixtureURL)
            let root = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            let thresholds = root["thresholds"] as! [[String: Any]]
            for item in thresholds {
                let percent = item["percent"] as! Double
                expect(MarketRules.bucket(for: percent)?.rawValue == item["pet"] as? String)
                expect(MarketTone.resolve(percent: percent).rawValue == item["tone"] as? String)
                expect(MarketRules.signedPercent(percent) == item["formatted"] as? String)
            }
        }
        run("percent calculation") {
            expect(abs(Quote.percent(lastPrice: 3012, previousClose: 3000) - 0.4) < 0.0001)
        }
        run("market target catalog and migration") {
            expect(MarketTarget.default.id == "ths-all")
            expect(MarketTarget.all.count == 6)
            expect(MarketTarget.target(id: "star50") == .star50)
            expect(MarketTarget.microCap.name == "微盘股（883418）")
            expect(MarketTarget.target(id: MarketTarget.microCap.id) == MarketTarget.microCap)
            expect(MarketTarget.tonghuashun(code: "123456")?.name == "代码（123456）")
            expect(MarketTarget.tonghuashun(code: "688365")?.eastmoneySecID == "1.688365")
            expect(MarketTarget.tonghuashun(code: "688365")?.tencentSymbol == "sh688365")
            expect(MarketTarget.tonghuashun(code: "510300")?.eastmoneySecID == "1.510300")
            expect(MarketTarget.tonghuashun(code: "510300")?.tencentSymbol == "sh510300")
            expect(MarketTarget.microCap.sourceKind == .tonghuashunPublic)
            expect(MarketTarget.tonghuashun(code: "12345") == nil)
            expect(MarketTarget.tonghuashun(code: "１２３４５６") == nil)
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
            let namedFixture = "<h3>同花顺全A（沪深）<span>883421</span></h3>"
            expect(TonghuashunHTMLParser.name(in: namedFixture) == "同花顺全A（沪深）")
        }
        await runAsync("macOS update metadata and version comparison") {
            let payload = """
            {
              "tag_name": "v1.2.0",
              "html_url": "https://github.com/callhong/niulai-market-pets/releases/tag/v1.2.0",
              "assets": [
                {"name":"NiuLaiMarketPets-1.2.0.dmg","browser_download_url":"https://github.com/callhong/niulai-market-pets/releases/download/v1.2.0/NiuLaiMarketPets-1.2.0.dmg"}
              ]
            }
            """
            let service = MacUpdateService(currentVersion: "1.1.0") { Data(payload.utf8) }
            let result = await service.check()
            expect(result.success)
            expect(result.isNewer)
            expect(result.latestVersion == "1.2.0")
            expect(result.release?.diskImageURL?.absoluteString.contains("1.2.0.dmg") == true)

            let current = MacUpdateService(currentVersion: "1.2.0") { Data(payload.utf8) }
            let currentResult = await current.check()
            expect(currentResult.success)
            expect(!currentResult.isNewer)
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
            let watchlist = PersistedState(watchlistCodes: ["688365", "510300", "688365"], watchlistPollingEnabled: true)
            expect(watchlist.watchlistCodes == ["688365", "510300"])
            expect(watchlist.watchlistPollingEnabled)
            let roundTrip = try! JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(watchlist))
            expect(roundTrip == watchlist)
        }
        run("notification policy boundary deduplication") {
            var policy = NotificationPolicy()
            let a = policy.shouldNotify(previousPercent: nil, currentPercent: 0, switchedTo: .niulai, mode: .auto, isInitialSample: true, isTargetRotation: false, isStale: false)
            let b = policy.shouldNotify(previousPercent: -0.01, currentPercent: 0, switchedTo: .niulai, mode: .auto, isInitialSample: false, isTargetRotation: false, isStale: false)
            let c = policy.shouldNotify(previousPercent: -0.02, currentPercent: 0.2, switchedTo: .niulai, mode: .auto, isInitialSample: false, isTargetRotation: false, isStale: false)
            let d = policy.shouldNotify(previousPercent: 0.9, currentPercent: 1.01, switchedTo: .baola, mode: .auto, isInitialSample: false, isTargetRotation: false, isStale: false)
            let e = policy.shouldNotify(previousPercent: 0.9, currentPercent: 1.01, switchedTo: .baola, mode: .auto, isInitialSample: false, isTargetRotation: false, isStale: false)
            let f = policy.shouldNotify(previousPercent: -0.1, currentPercent: 0.1, switchedTo: .niulai, mode: .auto, isInitialSample: false, isTargetRotation: true, isStale: false)
            expect(!a && b && !c && d && !e && !f)
            let csiQuote = Quote(symbol: MarketTarget.csiAll.symbol, name: "中证全指·实时名称", lastPrice: 4_012, previousClose: 4_000, quoteTimestamp: Date(), provider: "fixture")
            let body = NotificationPolicy.body(for: .baola, target: .csiAll, quote: csiQuote)
            expect(body.contains("中证全指·实时名称"))
            expect(!body.contains("上证指数"))
        }
        run("market snapshot freshness and pill migration") {
            let now = Date(timeIntervalSince1970: 10_000)
            let quote = Quote(symbol: MarketTarget.sse.symbol, name: MarketTarget.sse.name, lastPrice: 3012, previousClose: 3000, quoteTimestamp: now, provider: "fixture")
            let snapshot = MarketSnapshot(targetID: MarketTarget.sse.id, quote: quote, fetchedAt: now)
            expect(!snapshot.isStale(at: now.addingTimeInterval(59)))
            expect(snapshot.isStale(at: now.addingTimeInterval(61)))
            expect(snapshot.quote?.name == MarketTarget.sse.name)
            expect(snapshot.tone(at: now) == .positive)
            let legacy = "{\"activePetID\":\"niulai\",\"mode\":\"auto\",\"panelVisible\":true}"
            let decoded = try! JSONDecoder().decode(PersistedState.self, from: Data(legacy.utf8))
            expect(decoded.schemaVersion == 1)
            expect(decoded.showMarketPill)
            let hidden = PersistedState(showMarketPill: false)
            let roundTrip = try! JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(hidden))
            expect(!roundTrip.showMarketPill)
            expect(roundTrip.schemaVersion == 2)
        }
        run("click audio catalog and mute persistence") {
            expect(ClickAudioCatalog.names(for: .niulai) == ["niulai"])
            expect(ClickAudioCatalog.names(for: .baola) == ["baola"])
            expect(Set(ClickAudioCatalog.names(for: .muamua)) == ["muamua-mama-long", "muamua-mama-rescue"])
            expect(ClickAudioPlayer.normalizedVolume == 1.0)
            expect(MarketSoundPolicy.shouldPlay(event: .click, isMuted: false))
            expect(MarketSoundPolicy.shouldPlay(event: .manualSelection, isMuted: false))
            expect(MarketSoundPolicy.shouldPlay(event: .automaticShapeSwitch, isMuted: false))
            expect(!MarketSoundPolicy.shouldPlay(event: .targetRotation, isMuted: false))
            expect(!MarketSoundPolicy.shouldPlay(event: .automaticShapeSwitch, isMuted: true))
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
                expect(!model.isWatchlistPollingEnabled)
                model.selectTarget(.sse)
                expect(model.target == .sse)
                expect(model.isIndexPollingEnabled == false)
                let stock = MarketTarget.tonghuashun(code: "688365")!
                model.selectTarget(stock)
                expect(model.watchlistCodes == ["688365"])
                model.setWatchlistPollingEnabled(true)
                expect(model.isWatchlistPollingEnabled)
                expect(!model.isIndexPollingEnabled)
                model.setIndexPollingEnabled(true)
                expect(model.isIndexPollingEnabled)
                expect(!model.isWatchlistPollingEnabled)
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
        print("swift-test-harness: PASS")
    }

    static func run(_ name: String, _ body: () -> Void) {
        body()
        print("PASS: \(name)")
    }

    static func runAsync(_ name: String, _ body: () async -> Void) async {
        await body()
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
