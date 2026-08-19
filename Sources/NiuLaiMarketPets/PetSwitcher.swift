import Foundation
import AppKit
import ImageIO

public protocol CodexReloading: Sendable {
    func reload() -> Bool
}

public struct DeepLinkReloader: CodexReloading {
    public init() {}
    public func reload() -> Bool {
        // The Codex desktop deep link opens a remote-setup alert when the
        // desktop bridge has not been provisioned. Treat the on-disk config
        // write as the durable source of truth in that state and stay quiet.
        let setupConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/codex-app/config.json")
        guard FileManager.default.fileExists(atPath: setupConfig.path) else { return true }
        guard let url = URL(string: "codex://codex-app/apply-config") else { return false }
        return NSWorkspace.shared.open(url)
    }
}

public enum PetValidationError: Error, LocalizedError {
    case missingPackage(URL)
    case invalidManifest(URL)
    case missingSpritesheet(URL)

    public var errorDescription: String? {
        switch self {
        case .missingPackage(let url): return "Missing pet package: \(url.path)"
        case .invalidManifest(let url): return "Invalid pet manifest: \(url.path)"
        case .missingSpritesheet(let url): return "Missing pet spritesheet: \(url.path)"
        }
    }
}

public struct PetPackageValidator {
    public let petsRootURL: URL

    public init(petsRootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets")) {
        self.petsRootURL = petsRootURL
    }

    public func validate(_ pet: PetID) throws {
        let directory = petsRootURL.appendingPathComponent(pet.rawValue)
        let manifestURL = directory.appendingPathComponent("pet.json")
        let sheetURL = directory.appendingPathComponent("spritesheet.webp")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw PetValidationError.missingPackage(directory) }
        guard FileManager.default.fileExists(atPath: sheetURL.path) else { throw PetValidationError.missingSpritesheet(sheetURL) }
        guard
            let data = try? Data(contentsOf: manifestURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["id"] as? String == pet.rawValue,
            json["spriteVersionNumber"] as? Int == 2,
            json["spritesheetPath"] as? String == "spritesheet.webp"
        else { throw PetValidationError.invalidManifest(manifestURL) }
        guard
            let source = CGImageSourceCreateWithURL(sheetURL as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
            let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
            width == 1536,
            height == 2288
        else { throw PetValidationError.invalidManifest(manifestURL) }
    }
}

public final class PetSwitcher {
    public let validator: PetPackageValidator
    public let configEditor: ConfigEditor
    public let reloader: any CodexReloading

    public init(
        validator: PetPackageValidator = PetPackageValidator(),
        configEditor: ConfigEditor = ConfigEditor(),
        reloader: any CodexReloading = DeepLinkReloader()
    ) {
        self.validator = validator
        self.configEditor = configEditor
        self.reloader = reloader
    }

    @discardableResult
    public func switchTo(_ pet: PetID, current: PetID?) throws -> Bool {
        try validator.validate(pet)
        guard current != pet else { return false }
        let receipt = try configEditor.writeSelectedAvatar(pet.configValue)
        guard receipt.changed else { return false }
        if reloader.reload() { return true }
        try? configEditor.restore(receipt)
        throw SwitchError.reloadFailed
    }
}

public enum SwitchError: Error, LocalizedError {
    case reloadFailed
    public var errorDescription: String? { "Codex did not accept the apply-config deep link" }
}
