import Foundation

/// Pluggable persistence for radar awareness state.
/// Default production implementation: ``BlazeDBAwarenessStore``.
/// ``JSONAwarenessStore`` remains available for lightweight/testing scenarios.
public protocol AwarenessStoreProtocol: Sendable {
    func load(workspacePath: String) async throws -> [AgentRegistration]
    func save(workspacePath: String, registrations: [AgentRegistration]) async throws
    func upsert(workspacePath: String, registration: AgentRegistration) async throws
    func find(workspacePath: String, id: UUID) async throws -> AgentRegistration?
    func activeRegistrations(workspacePath: String) async throws -> [AgentRegistration]
    func recordSync(workspacePath: String, agentId: UUID, at: Date) async throws
}
