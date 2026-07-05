import Foundation
import BlazeDB

/// BlazeDB-backed awareness store — single-writer durable coordination state.
public actor BlazeDBAwarenessStore: AwarenessStoreProtocol {
    public init() {}

    private func canonical(_ workspacePath: String) -> String {
        WorkspacePath.canonical(workspacePath)
    }

    private func matchesWorkspace(_ rowPath: String, canonical: String) -> Bool {
        WorkspacePath.canonical(rowPath) == canonical
    }

    public func load(workspacePath: String) async throws -> [AgentRegistration] {
        let ws = canonical(workspacePath)
        let db = try await BlazeDBClientPool.shared.client(workspacePath: ws)
        let agents = try await db.fetchAll(RadarAgent.self).filter { matchesWorkspace($0.workspacePath, canonical: ws) }
        let findings = try await db.fetchAll(RadarFinding.self).filter { matchesWorkspace($0.workspacePath, canonical: ws) }
        let observations = try await db.fetchAll(RadarGitObservation.self).filter { matchesWorkspace($0.workspacePath, canonical: ws) }
        return agents.map { assemble(agent: $0, findings: findings, observations: observations) }
    }

    public func save(workspacePath: String, registrations: [AgentRegistration]) async throws {
        for registration in registrations {
            try await upsert(workspacePath: workspacePath, registration: registration)
        }
    }

    public func upsert(workspacePath: String, registration: AgentRegistration) async throws {
        let ws = canonical(workspacePath)
        let db = try await BlazeDBClientPool.shared.client(workspacePath: ws)
        let agent = RadarAgent(from: registration, workspacePath: ws)
        _ = try await db.upsert(agent)

        let existingFindings = try await db.fetchAll(RadarFinding.self)
            .filter { matchesWorkspace($0.workspacePath, canonical: ws) && $0.agentId == registration.id }

        try await appendMissingFindings(
            db: db,
            workspacePath: ws,
            agentId: registration.id,
            type: .discovered,
            messages: registration.discoveredFacts,
            existing: existingFindings
        )
        try await appendMissingFindings(
            db: db,
            workspacePath: ws,
            agentId: registration.id,
            type: .negated,
            messages: registration.negatedHypotheses,
            existing: existingFindings
        )
        try await appendMissingFindings(
            db: db,
            workspacePath: ws,
            agentId: registration.id,
            type: .invariant,
            messages: registration.invariantsChanged,
            existing: existingFindings
        )
        try await appendMissingFindings(
            db: db,
            workspacePath: ws,
            agentId: registration.id,
            type: .test,
            messages: registration.testsAdded,
            existing: existingFindings
        )
        try await appendMissingFindings(
            db: db,
            workspacePath: ws,
            agentId: registration.id,
            type: .question,
            messages: registration.openQuestions,
            existing: existingFindings
        )

        if let hypothesis = registration.hypothesis, !hypothesis.isEmpty {
            let hasHypothesis = existingFindings.contains {
                $0.type == RadarFindingType.hypothesis.rawValue && $0.message == hypothesis
            }
            if !hasHypothesis {
                try await db.insert(RadarFinding(
                    agentId: registration.id,
                    workspacePath: ws,
                    type: .hypothesis,
                    message: hypothesis
                ))
            }
        }

        if let headSHA = registration.headSHA, !headSHA.isEmpty {
            let latest = try await db.fetchAll(RadarGitObservation.self)
                .filter { matchesWorkspace($0.workspacePath, canonical: ws) && $0.agentId == registration.id }
                .sorted { $0.timestamp > $1.timestamp }
                .first
            let changed = latest?.headSHA != headSHA
                || latest?.branch != registration.branch
                || latest?.changedFiles != registration.changedFiles
            if latest == nil || changed {
                try await db.insert(RadarGitObservation(
                    agentId: registration.id,
                    workspacePath: ws,
                    branch: registration.branch,
                    headSHA: headSHA,
                    changedFiles: registration.changedFiles
                ))
            }
        }
    }

    public func find(workspacePath: String, id: UUID) async throws -> AgentRegistration? {
        let ws = canonical(workspacePath)
        let db = try await BlazeDBClientPool.shared.client(workspacePath: ws)
        guard let agent = try await db.fetch(RadarAgent.self, id: id),
              matchesWorkspace(agent.workspacePath, canonical: ws) else { return nil }
        let findings = try await db.fetchAll(RadarFinding.self)
            .filter { matchesWorkspace($0.workspacePath, canonical: ws) && $0.agentId == id }
        let observations = try await db.fetchAll(RadarGitObservation.self)
            .filter { matchesWorkspace($0.workspacePath, canonical: ws) && $0.agentId == id }
        return assemble(agent: agent, findings: findings, observations: observations)
    }

    public func activeRegistrations(workspacePath: String) async throws -> [AgentRegistration] {
        try await load(workspacePath: workspacePath).filter { $0.status.isOnBoard }
    }

    public func recordSync(workspacePath: String, agentId: UUID, at: Date) async throws {
        let ws = canonical(workspacePath)
        let db = try await BlazeDBClientPool.shared.client(workspacePath: ws)
        try await db.insert(RadarSyncState(agentId: agentId, workspacePath: ws, lastSyncAt: at))
    }

    private func appendMissingFindings(
        db: BlazeDBClient,
        workspacePath: String,
        agentId: UUID,
        type: RadarFindingType,
        messages: [String],
        existing: [RadarFinding]
    ) async throws {
        let existingMessages = Set(existing.filter { $0.type == type.rawValue }.map(\.message))
        for message in messages where !existingMessages.contains(message) {
            try await db.insert(RadarFinding(
                agentId: agentId,
                workspacePath: workspacePath,
                type: type,
                message: message
            ))
        }
    }

    private func assemble(
        agent: RadarAgent,
        findings: [RadarFinding],
        observations: [RadarGitObservation]
    ) -> AgentRegistration {
        let agentFindings = findings.filter { $0.agentId == agent.id }.sorted { $0.timestamp < $1.timestamp }
        let latestGit = observations.filter { $0.agentId == agent.id }.sorted { $0.timestamp > $1.timestamp }.first
        let status = AgentRegistrationStatus(rawValue: agent.status) ?? .active

        return AgentRegistration(
            id: agent.id,
            agentName: agent.agentName,
            task: agent.task,
            branch: latestGit?.branch ?? agent.branch,
            worktree: agent.worktree,
            status: status,
            headSHA: latestGit?.headSHA,
            changedFiles: latestGit?.changedFiles ?? [],
            hypothesis: agent.hypothesis,
            discoveredFacts: agentFindings.filter { $0.type == RadarFindingType.discovered.rawValue }.map(\.message),
            negatedHypotheses: agentFindings.filter { $0.type == RadarFindingType.negated.rawValue }.map(\.message),
            invariantsChanged: agentFindings.filter { $0.type == RadarFindingType.invariant.rawValue }.map(\.message),
            testsAdded: agentFindings.filter { $0.type == RadarFindingType.test.rawValue }.map(\.message),
            openQuestions: agentFindings.filter { $0.type == RadarFindingType.question.rawValue }.map(\.message),
            registeredAt: agent.registeredAt,
            lastSeen: agent.lastSeen,
            completedAt: agent.completedAt
        )
    }
}
