import Foundation

public enum PetID: String, CaseIterable, Codable, Sendable {
    case niulai
    case baola
    case muamua

    public var displayName: String {
        switch self {
        case .niulai: return "牛来"
        case .baola: return "豹拉"
        case .muamua: return "牛妈"
        }
    }

    public var shortSemantic: String {
        switch self {
        case .niulai: return "微涨／平盘"
        case .baola: return "明显上涨"
        case .muamua: return "下跌"
        }
    }
}

public enum ControlMode: String, Codable, Sendable {
    case auto
    case manual
}

/// A platform-neutral market color. UI layers map the hex value to their
/// native color type; keeping the decision here prevents blue/down or stale
/// values from drifting between macOS and Windows.
public enum MarketTone: String, Codable, Sendable {
    case positive
    case negative
    case neutral
    case unavailable

    public static func resolve(percent: Double?, isStale: Bool = false) -> MarketTone {
        guard let percent, percent.isFinite, !isStale else { return .unavailable }
        if percent > 0 { return .positive }
        if percent < 0 { return .negative }
        return .neutral
    }

    public var colorHex: String {
        switch self {
        case .positive: return "#E24B4B"
        case .negative: return "#2F9A62"
        case .neutral, .unavailable: return "#8A8F98"
        }
    }
}

public enum PetScaleRange {
    public static let minPercent = 60.0
    public static let maxPercent = 160.0
    public static let defaultPercent = 100.0

    public static func clamped(_ percent: Double) -> Double {
        guard percent.isFinite else { return defaultPercent }
        return min(max(percent, minPercent), maxPercent)
    }
}

public enum SpeechTextScaleRange {
    public static let minPercent = 80.0
    public static let maxPercent = 140.0
    public static let defaultPercent = 100.0

    public static func clamped(_ percent: Double) -> Double {
        guard percent.isFinite else { return defaultPercent }
        return min(max(percent, minPercent), maxPercent)
    }
}

/// A replaceable market target. Provider-specific routing stays outside the
/// state machine and UI, while the stable ID is persisted across launches.
public struct MarketTarget: Codable, Equatable, Sendable {
    public let id: String
    public let symbol: String
    public let name: String
    public let eastmoneySecID: String?
    public let tencentSymbol: String?
    public let sourceKind: SourceKind

    public enum SourceKind: String, Codable, Sendable {
        case standardIndex
        case tonghuashunPublic
    }

    public init(
        id: String,
        symbol: String,
        name: String,
        eastmoneySecID: String?,
        tencentSymbol: String?,
        sourceKind: SourceKind = .standardIndex
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.eastmoneySecID = eastmoneySecID
        self.tencentSymbol = tencentSymbol
        self.sourceKind = sourceKind
    }

    public static let sse = MarketTarget(
        id: "sse",
        symbol: "000001",
        name: "上证指数",
        eastmoneySecID: "1.000001",
        tencentSymbol: "sh000001"
    )

    public static let thsAll = MarketTarget(
        id: "ths-all",
        symbol: "883421",
        name: "同花顺全A（沪深）",
        eastmoneySecID: nil,
        tencentSymbol: nil,
        sourceKind: .tonghuashunPublic
    )

    public static let microCap = tonghuashun(code: "883418")!

    public static let csiAll = MarketTarget(
        id: "csi-all",
        symbol: "000985",
        name: "中证全指",
        eastmoneySecID: "1.000985",
        tencentSymbol: "sh000985"
    )

    public static let cni2000 = MarketTarget(
        id: "cni-2000",
        symbol: "399303",
        name: "国证2000",
        eastmoneySecID: "0.399303",
        tencentSymbol: "sz399303"
    )

    public static let chinext = MarketTarget(
        id: "chinext",
        symbol: "399006",
        name: "创业板指",
        eastmoneySecID: "0.399006",
        tencentSymbol: "sz399006"
    )

    public static let star50 = MarketTarget(
        id: "star50",
        symbol: "000688",
        name: "科创50",
        eastmoneySecID: "1.000688",
        tencentSymbol: "sh000688"
    )

    public static let all: [MarketTarget] = [sse, csiAll, thsAll, chinext, star50, cni2000]
    public static let `default` = thsAll

    public static func target(id: String) -> MarketTarget {
        if let fixed = all.first(where: { $0.id == id }) { return fixed }
        if id == microCap.id { return microCap }
        let prefix = "ths-code-"
        if id.hasPrefix(prefix),
           let custom = tonghuashun(code: String(id.dropFirst(prefix.count))) {
            return custom
        }
        return `default`
    }

    public static func tonghuashun(code: String) -> MarketTarget? {
        guard code.utf8.count == 6,
              code.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        let name = code == "883418" ? "微盘股（883418）" : "同花顺（\(code)）"
        return MarketTarget(
            id: "ths-code-\(code)",
            symbol: code,
            name: name,
            eastmoneySecID: nil,
            tencentSymbol: nil,
            sourceKind: .tonghuashunPublic
        )
    }

    public static func nextPollingTarget(after id: String) -> MarketTarget {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return all[0] }
        return all[(index + 1) % all.count]
    }
}

public struct Quote: Codable, Equatable, Sendable {
    public let symbol: String
    public let name: String
    public let lastPrice: Double
    public let previousClose: Double
    public let percent: Double
    public let quoteTimestamp: Date
    public let provider: String
    public let isStale: Bool

    public init(
        symbol: String = "000001",
        name: String = "上证指数",
        lastPrice: Double,
        previousClose: Double,
        quoteTimestamp: Date,
        provider: String,
        isStale: Bool = false
    ) {
        self.symbol = symbol
        self.name = name
        self.lastPrice = lastPrice
        self.previousClose = previousClose
        self.percent = Quote.percent(lastPrice: lastPrice, previousClose: previousClose)
        self.quoteTimestamp = quoteTimestamp
        self.provider = provider
        self.isStale = isStale
    }

    public static func percent(lastPrice: Double, previousClose: Double) -> Double {
        guard previousClose.isFinite, previousClose > 0, lastPrice.isFinite else { return .nan }
        return (lastPrice - previousClose) / previousClose * 100
    }
}

public struct MarketSnapshot: Codable, Equatable, Sendable {
    public let targetID: String
    public var quote: Quote?
    public var fetchedAt: Date?
    public var lastError: String?

    public init(
        targetID: String,
        quote: Quote? = nil,
        fetchedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.targetID = targetID
        self.quote = quote
        self.fetchedAt = fetchedAt
        self.lastError = lastError
    }

    public func isStale(at date: Date, maxAge: TimeInterval = 60) -> Bool {
        guard let quote, !quote.isStale, quote.percent.isFinite, let fetchedAt else { return true }
        if date.timeIntervalSince(fetchedAt) > maxAge { return true }
        return date.timeIntervalSince(quote.quoteTimestamp) > 300
    }

    public func tone(at date: Date, maxAge: TimeInterval = 60) -> MarketTone {
        MarketTone.resolve(percent: quote?.percent, isStale: isStale(at: date, maxAge: maxAge))
    }
}

public struct PersistedState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var targetID: String
    public var mode: ControlMode
    public var manualPetID: PetID?
    public var activePetID: PetID
    public var lastMarketPercent: Double?
    public var lastQuoteAt: Date?
    public var lastProvider: String?
    public var panelVisible: Bool
    public var panelX: Double?
    public var panelY: Double?
    public var petScalePercent: Double
    public var speechTextScalePercent: Double
    public var indexPollingEnabled: Bool
    public var isMuted: Bool
    public var showMarketPill: Bool

    public init(
        schemaVersion: Int = 2,
        targetID: String = MarketTarget.default.id,
        mode: ControlMode = .auto,
        manualPetID: PetID? = nil,
        activePetID: PetID = .niulai,
        lastMarketPercent: Double? = nil,
        lastQuoteAt: Date? = nil,
        lastProvider: String? = nil,
        panelVisible: Bool = true,
        panelX: Double? = nil,
        panelY: Double? = nil,
        petScalePercent: Double = PetScaleRange.defaultPercent,
        speechTextScalePercent: Double = SpeechTextScaleRange.defaultPercent,
        indexPollingEnabled: Bool = false,
        isMuted: Bool = false,
        showMarketPill: Bool = true
    ) {
        self.schemaVersion = max(1, schemaVersion)
        self.targetID = targetID
        self.mode = mode
        self.manualPetID = manualPetID
        self.activePetID = activePetID
        self.lastMarketPercent = lastMarketPercent
        self.lastQuoteAt = lastQuoteAt
        self.lastProvider = lastProvider
        self.panelVisible = panelVisible
        self.panelX = panelX
        self.panelY = panelY
        self.petScalePercent = PetScaleRange.clamped(petScalePercent)
        self.speechTextScalePercent = SpeechTextScaleRange.clamped(speechTextScalePercent)
        self.indexPollingEnabled = indexPollingEnabled
        self.isMuted = isMuted
        self.showMarketPill = showMarketPill
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, targetID, mode, manualPetID, activePetID, lastMarketPercent, lastQuoteAt, lastProvider
        case panelVisible, panelX, panelY, petScalePercent, speechTextScalePercent, indexPollingEnabled
        case isMuted, showMarketPill
        case legacyPetScale = "petScale"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        targetID = try values.decodeIfPresent(String.self, forKey: .targetID) ?? MarketTarget.default.id
        mode = try values.decode(ControlMode.self, forKey: .mode)
        manualPetID = try values.decodeIfPresent(PetID.self, forKey: .manualPetID)
        activePetID = try values.decode(PetID.self, forKey: .activePetID)
        lastMarketPercent = try values.decodeIfPresent(Double.self, forKey: .lastMarketPercent)
        lastQuoteAt = try values.decodeIfPresent(Date.self, forKey: .lastQuoteAt)
        lastProvider = try values.decodeIfPresent(String.self, forKey: .lastProvider)
        panelVisible = try values.decode(Bool.self, forKey: .panelVisible)
        panelX = try values.decodeIfPresent(Double.self, forKey: .panelX)
        panelY = try values.decodeIfPresent(Double.self, forKey: .panelY)
        if let percent = try values.decodeIfPresent(Double.self, forKey: .petScalePercent) {
            petScalePercent = PetScaleRange.clamped(percent)
        } else if let legacy = try values.decodeIfPresent(String.self, forKey: .legacyPetScale) {
            switch legacy {
            case "small": petScalePercent = 82
            case "large": petScalePercent = 118
            default: petScalePercent = PetScaleRange.defaultPercent
            }
        } else {
            petScalePercent = PetScaleRange.defaultPercent
        }
        speechTextScalePercent = SpeechTextScaleRange.clamped(
            try values.decodeIfPresent(Double.self, forKey: .speechTextScalePercent) ?? SpeechTextScaleRange.defaultPercent
        )
        indexPollingEnabled = try values.decodeIfPresent(Bool.self, forKey: .indexPollingEnabled) ?? false
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        showMarketPill = try values.decodeIfPresent(Bool.self, forKey: .showMarketPill) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(targetID, forKey: .targetID)
        try values.encode(mode, forKey: .mode)
        try values.encodeIfPresent(manualPetID, forKey: .manualPetID)
        try values.encode(activePetID, forKey: .activePetID)
        try values.encodeIfPresent(lastMarketPercent, forKey: .lastMarketPercent)
        try values.encodeIfPresent(lastQuoteAt, forKey: .lastQuoteAt)
        try values.encodeIfPresent(lastProvider, forKey: .lastProvider)
        try values.encode(panelVisible, forKey: .panelVisible)
        try values.encodeIfPresent(panelX, forKey: .panelX)
        try values.encodeIfPresent(panelY, forKey: .panelY)
        try values.encode(petScalePercent, forKey: .petScalePercent)
        try values.encode(speechTextScalePercent, forKey: .speechTextScalePercent)
        try values.encode(indexPollingEnabled, forKey: .indexPollingEnabled)
        try values.encode(isMuted, forKey: .isMuted)
        try values.encode(showMarketPill, forKey: .showMarketPill)
    }
}

public struct QuoteFetchResult: Sendable {
    public let quote: Quote?
    public let errors: [String]

    public init(quote: Quote?, errors: [String] = []) {
        self.quote = quote
        self.errors = errors
    }
}

public enum MarketSession: String, Sendable {
    case preOpen = "集合竞价"
    case trading = "交易中"
    case lunch = "午休"
    case closed = "已收盘"
    case stale = "数据陈旧"
    case offline = "离线"

    public var allowsAutomaticSwitch: Bool { self == .trading }
}
