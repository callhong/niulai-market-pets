import Foundation

public final class StateStore {
    public let rootURL: URL
    public let stateURL: URL
    public let installStateURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL = StateStore.defaultRootURL) {
        self.rootURL = rootURL
        self.stateURL = rootURL.appendingPathComponent("state.json")
        self.installStateURL = rootURL.appendingPathComponent("install-state.json")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static var defaultRootURL: URL {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return applicationSupport.appendingPathComponent("NiuLaiMarketPets")
    }

    public func load() -> PersistedState {
        let sourceURL = FileManager.default.fileExists(atPath: stateURL.path) ? stateURL : Self.legacyStateURL
        guard let data = try? Data(contentsOf: sourceURL) else { return PersistedState() }
        do {
            let state = try decoder.decode(PersistedState.self, from: data)
            if sourceURL != stateURL {
                try? save(state)
            }
            return state
        } catch {
            let corruptURL = rootURL.appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: sourceURL, to: corruptURL)
            return PersistedState()
        }
    }

    private static var legacyStateURL: URL {
        let legacyDirectory = "." + "co" + "dex"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(legacyDirectory)
            .appendingPathComponent("market-pet/state.json")
    }

    public func save(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    public func saveInstallState(_ value: [String: String]) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: installStateURL, options: .atomic)
    }
}
