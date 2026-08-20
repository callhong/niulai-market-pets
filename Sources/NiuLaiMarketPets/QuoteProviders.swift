import Foundation

public protocol QuoteProviding: Sendable {
    var name: String { get }
    func fetch() async throws -> Quote
}

public struct EastmoneyQuoteProvider: QuoteProviding {
    public let name = "eastmoney"
    public let target: MarketTarget
    private let session: URLSession

    public init(target: MarketTarget = .sse, session: URLSession = .shared) {
        self.target = target
        self.session = session
    }

    public func fetch() async throws -> Quote {
        guard let secID = target.eastmoneySecID else { throw ProviderError.unsupportedTarget }
        var components = URLComponents(string: "https://push2.eastmoney.com/api/qt/stock/get")!
        components.queryItems = [
            URLQueryItem(name: "secid", value: secID),
            URLQueryItem(name: "fields", value: "f43,f60,f58,f86"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 NiuLaiMarketPets/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProviderError.invalidHTTP
        }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = root["data"] as? [String: Any],
            let rawLast = number(payload["f43"]),
            let rawPrevious = number(payload["f60"]),
            rawLast > 0,
            rawPrevious > 0
        else { throw ProviderError.invalidPayload }
        let timestamp = timestampFromEastmoney(payload["f86"]) ?? Date()
        return Quote(
            symbol: target.symbol,
            name: target.name,
            lastPrice: rawLast / 100,
            previousClose: rawPrevious / 100,
            quoteTimestamp: timestamp,
            provider: name
        )
    }
}

public struct TencentQuoteProvider: QuoteProviding {
    public let name = "tencent"
    public let target: MarketTarget
    private let session: URLSession

    public init(target: MarketTarget = .sse, session: URLSession = .shared) {
        self.target = target
        self.session = session
    }

    public func fetch() async throws -> Quote {
        guard let symbol = target.tencentSymbol else { throw ProviderError.unsupportedTarget }
        var request = URLRequest(url: URL(string: "https://qt.gtimg.cn/q=\(symbol)")!)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 NiuLaiMarketPets/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProviderError.invalidHTTP
        }
        let text = String(decoding: data, as: UTF8.self)
        let fields = text.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard fields.count > 5, let last = Double(fields[3]), let previous = Double(fields[4]), previous > 0 else {
            throw ProviderError.invalidPayload
        }
        let date = fields.count > 30 ? fields[30] : ""
        let time = fields.count > 31 ? fields[31] : ""
        let timestamp = timestampFromTencent(date: date, time: time) ?? Date()
        return Quote(
            symbol: target.symbol,
            name: target.name,
            lastPrice: last,
            previousClose: previous,
            quoteTimestamp: timestamp,
            provider: name
        )
    }
}

/// Public Tonghuashun index page provider used for the selected six-digit
/// target, including the built-in 883418 micro-cap indicator. The page is
/// GBK, but all fields needed here are ASCII numbers and HTML markers, so
/// parsing the raw byte-preserving UTF-8 view is sufficient.
public struct TonghuashunPublicQuoteProvider: QuoteProviding {
    public let name = "tonghuashun-public"
    public let target: MarketTarget
    private let session: URLSession

    public init(target: MarketTarget = .thsAll, session: URLSession = .shared) {
        self.target = target
        self.session = session
    }

    public func fetch() async throws -> Quote {
        guard target.sourceKind == .tonghuashunPublic else { throw ProviderError.unsupportedTarget }
        var request = URLRequest(url: URL(string: "https://q.10jqka.com.cn/thshy/detail/code/\(target.symbol)/")!)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 NiuLaiMarketPets/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProviderError.invalidHTTP
        }
        let html = String(decoding: data, as: UTF8.self)
        guard
            let last = TonghuashunHTMLParser.lastPrice(in: html),
            let previous = TonghuashunHTMLParser.previousClose(in: html),
            last > 0,
            previous > 0
        else { throw ProviderError.invalidPayload }
        return Quote(
            symbol: target.symbol,
            name: target.name,
            lastPrice: last,
            previousClose: previous,
            quoteTimestamp: Date(),
            provider: name
        )
    }
}

/// Optional licensed fallback. It stays deliberately disabled without an
/// explicit user-provided token; a different index must never be substituted
/// for 883421 when the public page is unavailable.
public struct TonghuashunAuthorizedQuoteProvider: QuoteProviding {
    public let name = "tonghuashun-ifind"
    public let target: MarketTarget

    public init(target: MarketTarget = .thsAll) {
        self.target = target
    }

    public func fetch() async throws -> Quote {
        guard let token = ProcessInfo.processInfo.environment["THS_ACCESS_TOKEN"], !token.isEmpty else {
            throw ProviderError.missingAuthorization
        }
        _ = token
        throw ProviderError.invalidPayload
    }
}

public struct QuoteService: Sendable {
    public let primary: any QuoteProviding
    public let backup: any QuoteProviding

    public init(primary: any QuoteProviding, backup: any QuoteProviding) {
        self.primary = primary
        self.backup = backup
    }

    public init() {
        self.init(target: .default)
    }

    public init(target: MarketTarget, session: URLSession = .shared) {
        if target.sourceKind == .tonghuashunPublic {
            self.primary = TonghuashunPublicQuoteProvider(target: target, session: session)
            self.backup = TonghuashunAuthorizedQuoteProvider(target: target)
        } else {
            self.primary = EastmoneyQuoteProvider(target: target, session: session)
            self.backup = TencentQuoteProvider(target: target, session: session)
        }
    }

    public func fetch() async -> QuoteFetchResult {
        var errors: [String] = []
        do {
            return QuoteFetchResult(quote: try await primary.fetch(), errors: [])
        } catch {
            errors.append("\(primary.name): \(error.localizedDescription)")
        }
        do {
            return QuoteFetchResult(quote: try await backup.fetch(), errors: errors)
        } catch {
            errors.append("\(backup.name): \(error.localizedDescription)")
            return QuoteFetchResult(quote: nil, errors: errors)
        }
    }
}

public enum ProviderError: Error, LocalizedError {
    case invalidHTTP
    case invalidPayload
    case unsupportedTarget
    case missingAuthorization

    public var errorDescription: String? {
        switch self {
        case .invalidHTTP: return "HTTP response was not successful"
        case .invalidPayload: return "Quote payload was invalid"
        case .unsupportedTarget: return "Quote target is not supported by this provider"
        case .missingAuthorization: return "Licensed provider is not configured"
        }
    }
}

enum TonghuashunHTMLParser {
    static func lastPrice(in html: String) -> Double? {
        guard let value = value(after: "<span class=\"board-xj", before: "</span>", in: html) else { return nil }
        return number(value)
    }

    static func previousClose(in html: String) -> Double? {
        guard let start = html.range(of: "<div class=\"board-infos\"") else { return nil }
        guard let end = html.range(of: "</div>", range: start.upperBound..<html.endIndex) else { return nil }
        let section = String(html[start.upperBound..<end.lowerBound])
        var values: [String] = []
        var cursor = section.startIndex
        while let dd = section.range(of: "<dd", range: cursor..<section.endIndex),
              let open = section.range(of: ">", range: dd.upperBound..<section.endIndex),
              let close = section.range(of: "</dd>", range: open.upperBound..<section.endIndex) {
            values.append(String(section[open.upperBound..<close.lowerBound]))
            cursor = close.upperBound
        }
        guard values.count > 1 else { return nil }
        return number(values[1])
    }

    private static func value(after marker: String, before endMarker: String, in html: String) -> String? {
        guard let start = html.range(of: marker),
              let open = html.range(of: ">", range: start.upperBound..<html.endIndex),
              let end = html.range(of: endMarker, range: open.upperBound..<html.endIndex)
        else { return nil }
        return String(html[open.upperBound..<end.lowerBound])
    }

    private static func number(_ value: String) -> Double? {
        let clean = value
            .replacingOccurrences(of: "&nbsp;", with: "")
            .replacingOccurrences(of: "\u{a0}", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scalarStart = clean.firstIndex(where: { $0.isNumber || $0 == "-" || $0 == "." })
        guard let scalarStart else { return nil }
        let suffix = clean[scalarStart...]
        let numeric = suffix.prefix { $0.isNumber || $0 == "-" || $0 == "." }
        return Double(numeric)
    }
}

private func number(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
}

private func timestampFromEastmoney(_ value: Any?) -> Date? {
    guard let number = number(value), number > 0 else { return nil }
    let date = Date(timeIntervalSince1970: number)
    return date > Date(timeIntervalSince1970: 946684800) ? date : nil
}

private func timestampFromTencent(date: String, time: String) -> Date? {
    guard !date.isEmpty else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = MarketRules.shanghaiCalendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = time.isEmpty ? "yyyyMMdd" : "yyyyMMdd HHmmss"
    return formatter.date(from: time.isEmpty ? date : "\(date) \(time)")
}
