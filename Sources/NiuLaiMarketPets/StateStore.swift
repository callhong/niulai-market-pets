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
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/market-pet")
    }

    public func load() -> PersistedState {
        guard let data = try? Data(contentsOf: stateURL) else { return PersistedState() }
        do {
            return try decoder.decode(PersistedState.self, from: data)
        } catch {
            let corruptURL = rootURL.appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: stateURL, to: corruptURL)
            return PersistedState()
        }
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
