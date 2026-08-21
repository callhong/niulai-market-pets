import Foundation

public struct MacUpdateRelease: Equatable, Sendable {
    public let tagName: String
    public let htmlURL: URL
    public let diskImageURL: URL?

    public init(tagName: String, htmlURL: URL, diskImageURL: URL?) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.diskImageURL = diskImageURL
    }
}

public struct MacUpdateCheckResult: Equatable, Sendable {
    public let success: Bool
    public let isNewer: Bool
    public let currentVersion: String
    public let latestVersion: String
    public let release: MacUpdateRelease?
    public let message: String

    public init(
        success: Bool,
        isNewer: Bool,
        currentVersion: String,
        latestVersion: String,
        release: MacUpdateRelease?,
        message: String
    ) {
        self.success = success
        self.isNewer = isNewer
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.release = release
        self.message = message
    }
}

/// Public-release update check for the native macOS client.
///
/// The service only checks metadata. Opening the official DMG is an explicit
/// user action in AppKit, so the app never silently replaces itself.
public struct MacUpdateService: Sendable {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/callhong/niulai-market-pets/releases/latest")!

    private let currentVersion: String
    private let dataProvider: @Sendable () async throws -> Data

    public init(
        currentVersion: String,
        session: URLSession = .shared,
        latestReleaseURL: URL = MacUpdateService.latestReleaseURL
    ) {
        self.currentVersion = currentVersion
        self.dataProvider = {
            var request = URLRequest(url: latestReleaseURL)
            request.timeoutInterval = 30
            request.setValue("NiuLaiMarketPets.macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UpdateServiceError.invalidHTTP
            }
            return data
        }
    }

    init(currentVersion: String, dataProvider: @escaping @Sendable () async throws -> Data) {
        self.currentVersion = currentVersion
        self.dataProvider = dataProvider
    }

    public func check() async -> MacUpdateCheckResult {
        do {
            let data = try await dataProvider()
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tag = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let latest = SemanticVersion(tag) else {
                return MacUpdateCheckResult(
                    success: false,
                    isNewer: false,
                    currentVersion: currentVersion,
                    latestVersion: tag,
                    release: nil,
                    message: "发布版本号无法识别。"
                )
            }

            let current = SemanticVersion(currentVersion) ?? SemanticVersion("0.0.0")!
            guard latest > current else {
                return MacUpdateCheckResult(
                    success: true,
                    isNewer: false,
                    currentVersion: currentVersion,
                    latestVersion: latest.displayValue,
                    release: nil,
                    message: ""
                )
            }

            let pageURL = URL(string: release.htmlURL) ?? URL(string: "https://github.com/callhong/niulai-market-pets/releases")!
            let expectedDMGName = "NiuLaiMarketPets-\(latest.displayValue).dmg"
            let diskImageURL = release.assets?.first(where: {
                $0.name.caseInsensitiveCompare(expectedDMGName) == .orderedSame
            }).flatMap { URL(string: $0.browserDownloadURL) }
            let macRelease = MacUpdateRelease(tagName: tag, htmlURL: pageURL, diskImageURL: diskImageURL)
            return MacUpdateCheckResult(
                success: true,
                isNewer: true,
                currentVersion: currentVersion,
                latestVersion: latest.displayValue,
                release: macRelease,
                message: ""
            )
        } catch is CancellationError {
            return MacUpdateCheckResult(
                success: false,
                isNewer: false,
                currentVersion: currentVersion,
                latestVersion: "",
                release: nil,
                message: "检查更新已取消。"
            )
        } catch {
            return MacUpdateCheckResult(
                success: false,
                isNewer: false,
                currentVersion: currentVersion,
                latestVersion: "",
                release: nil,
                message: "暂时无法连接更新服务，请稍后重试。"
            )
        }
    }
}

private enum UpdateServiceError: Error {
    case invalidHTTP
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct SemanticVersion: Comparable {
    let components: [Int]

    init?(_ rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "v" || $0 == "V" })
        let values = normalized.split(separator: ".").map(String.init)
        guard !values.isEmpty,
              values.allSatisfy({ value in value.allSatisfy { $0.isNumber } }) else {
            return nil
        }
        self.components = values.map { Int($0) ?? 0 }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    var displayValue: String {
        components.map(String.init).joined(separator: ".")
    }
}
