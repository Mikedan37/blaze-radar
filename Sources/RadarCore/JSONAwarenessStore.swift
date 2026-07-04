import Foundation

/// JSON file adapter — optional lightweight store for tests or environments without BlazeDB.
/// Not the production source of truth when ``BlazeDBAwarenessStore`` is active.
public actor JSONAwarenessStore: AwarenessStoreProtocol {
    private struct PersistedState: Codable {
        var registrations: [AgentRegistration]
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func load(workspacePath: String) async throws -> [AgentRegistration] {
        let url = stateURL(workspacePath: workspacePath)
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(PersistedState.self, from: data) else {
            return []
        }
        return state.registrations
    }

    public func save(workspacePath: String, registrations: [AgentRegistration]) async throws {
        let url = stateURL(workspacePath: workspacePath)
        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = PersistedState(registrations: registrations)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    public func upsert(workspacePath: String, registration: AgentRegistration) async throws {
        var all = try await load(workspacePath: workspacePath)
        if let idx = all.firstIndex(where: { $0.id == registration.id }) {
            all[idx] = registration
        } else {
            all.append(registration)
        }
        try await save(workspacePath: workspacePath, registrations: all)
    }

    public func find(workspacePath: String, id: UUID) async throws -> AgentRegistration? {
        try await load(workspacePath: workspacePath).first { $0.id == id }
    }

    public func activeRegistrations(workspacePath: String) async throws -> [AgentRegistration] {
        try await load(workspacePath: workspacePath).filter { $0.status == .active }
    }

    public func recordSync(workspacePath: String, agentId: UUID, at: Date) async throws {
        // JSON adapter does not persist sync history.
    }

    private func stateURL(workspacePath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".blaze/awareness/state.json")
    }
}
