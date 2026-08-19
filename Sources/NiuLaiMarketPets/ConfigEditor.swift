import Foundation

public struct ConfigWriteReceipt: Sendable {
    public let backupURL: URL?
    public let changed: Bool
}

public final class ConfigEditor {
    public let configURL: URL
    public let backupDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml"),
        backupDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.configURL = configURL
        self.backupDirectoryURL = backupDirectoryURL ?? StateStore.defaultRootURL.appendingPathComponent("config-backups")
        self.fileManager = fileManager
    }

    public func read() throws -> String { try String(contentsOf: configURL, encoding: .utf8) }

    public func selectedAvatar(in content: String) -> String? {
        let lines = content.components(separatedBy: "\n")
        var inDesktop = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inDesktop = trimmed == "[desktop]"
                continue
            }
            guard inDesktop else { continue }
            if let range = line.range(of: #"^\s*selected-avatar-id\s*=\s*"#, options: .regularExpression) {
                let remainder = line[range.upperBound...]
                if let quoteStart = remainder.firstIndex(of: "\""), let quoteEnd = remainder[remainder.index(after: quoteStart)...].firstIndex(of: "\"") {
                    return String(remainder[remainder.index(after: quoteStart)..<quoteEnd])
                }
            }
        }
        return nil
    }

    public func replacingSelectedAvatar(in content: String, with value: String) -> String {
        var lines = content.components(separatedBy: "\n")
        var desktopIndex: Int?
        var desktopEnd = lines.count
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "[desktop]" { desktopIndex = index; continue }
            if desktopIndex != nil, index > desktopIndex!, trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                desktopEnd = index
                break
            }
        }

        let replacement = "selected-avatar-id = \"\(value.replacingOccurrences(of: "\\\"", with: ""))\""
        if let start = desktopIndex {
            for index in (start + 1)..<desktopEnd {
                if lines[index].range(of: #"^\s*selected-avatar-id\s*="#, options: .regularExpression) != nil {
                    let indentation = String(lines[index].prefix { $0 == " " || $0 == "\t" })
                    lines[index] = indentation + replacement
                    return lines.joined(separator: "\n")
                }
            }
            lines.insert(replacement, at: start + 1)
            return lines.joined(separator: "\n")
        }

        if !lines.isEmpty, !lines.last!.isEmpty { lines.append("") }
        lines.append(contentsOf: ["[desktop]", replacement])
        return lines.joined(separator: "\n")
    }

    @discardableResult
    public func writeSelectedAvatar(_ value: String) throws -> ConfigWriteReceipt {
        let original = try read()
        guard selectedAvatar(in: original) != value else { return ConfigWriteReceipt(backupURL: nil, changed: false) }
        let backup = try createBackup()
        let updated = replacingSelectedAvatar(in: original, with: value)
        try atomicWrite(updated)
        return ConfigWriteReceipt(backupURL: backup, changed: true)
    }

    public func restore(_ receipt: ConfigWriteReceipt) throws {
        guard let backupURL = receipt.backupURL else { return }
        try fileManager.removeItem(at: configURL)
        try fileManager.copyItem(at: backupURL, to: configURL)
    }

    private func createBackup() throws -> URL {
        try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = backupDirectoryURL.appendingPathComponent("config-\(stamp)-\(UUID().uuidString.prefix(6)).toml")
        try fileManager.copyItem(at: configURL, to: backup)
        let backups = try fileManager.contentsOfDirectory(at: backupDirectoryURL, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "toml" }
            .sorted { (lhs, rhs) in
                let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return l > r
            }
        for old in backups.dropFirst(5) { try? fileManager.removeItem(at: old) }
        return backup
    }

    private func atomicWrite(_ content: String) throws {
        let directory = configURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".niulai-config-\(UUID().uuidString).tmp")
        let attributes = try? fileManager.attributesOfItem(atPath: configURL.path)
        try content.data(using: .utf8)!.write(to: temporary)
        if let attributes { try? fileManager.setAttributes(attributes, ofItemAtPath: temporary.path) }
        if fileManager.fileExists(atPath: configURL.path) { try fileManager.removeItem(at: configURL) }
        try fileManager.moveItem(at: temporary, to: configURL)
    }
}
