import Foundation
import os

public actor AwarenessService {
    private static let logger = Logger(subsystem: "dev.blazeradar", category: "AwarenessService")

    private let store: any AwarenessStoreProtocol
    private let activeInterval: TimeInterval = 30 * 60
    private let idleInterval: TimeInterval = 6 * 3600

    public init(store: (any AwarenessStoreProtocol)? = nil) {
        self.store = store ?? BlazeDBAwarenessStore()
    }

    public func register(
        workspacePath: String,
        agentName: String,
        task: String,
        branch: String?,
        worktree: String?
    ) async throws -> AgentRegistration {
        let ws = WorkspacePath.canonical(workspacePath)
        let resolvedWorktree = WorkspacePath.canonical(worktree ?? ws)
        let resolvedBranch = branch ?? detectBranch(worktree: resolvedWorktree) ?? "unknown"

        let registration = AgentRegistration(
            agentName: agentName,
            task: task,
            branch: resolvedBranch,
            worktree: resolvedWorktree
        )

        try await store.upsert(workspacePath: ws, registration: registration)
        await WorkspaceRegistry.shared.note(ws)
        _ = await refreshGit(workspacePath: ws, registrationId: registration.id)
        return registration
    }

    public func sync(workspacePath: String, registrationId: UUID?) async -> SyncResult {
        let ws = WorkspacePath.canonical(workspacePath)
        await WorkspaceRegistry.shared.note(ws)
        var warnings: [String] = []
        var gitRefreshed = true

        let gitOutcome = await refreshGitForWorkspace(ws)
        if !gitOutcome.allSucceeded {
            gitRefreshed = false
            warnings.append("git refresh failed for \(gitOutcome.failedCount) agent(s)")
        }

        var heartbeatUpdated = false
        if let registrationId {
            do {
                if var reg = try await store.find(workspacePath: ws, id: registrationId),
                   reg.status.isOnBoard {
                    reg.lastSeen = Date()
                    if reg.status != .observing {
                        reg.status = .active
                    }
                    try await store.upsert(workspacePath: ws, registration: reg)
                    try await store.recordSync(workspacePath: ws, agentId: registrationId, at: Date())
                    heartbeatUpdated = true
                }
            } catch {
                Self.logger.warning("sync heartbeat failed: \(error.localizedDescription, privacy: .public)")
                warnings.append("heartbeat update failed")
            }
        }

        let snapshot = await getActiveWork(workspacePath: ws, excludeId: nil)
        return SyncResult(
            snapshot: snapshot,
            heartbeatUpdated: heartbeatUpdated,
            gitRefreshed: gitRefreshed,
            warnings: warnings
        )
    }

    public func getActiveWork(workspacePath: String, excludeId: UUID? = nil) async -> ActiveWorkSnapshot {
        let ws = WorkspacePath.canonical(workspacePath)
        await refreshPresenceStatus(workspacePath: ws)
        var active = (try? await store.activeRegistrations(workspacePath: ws)) ?? []
        if let excludeId {
            active = active.filter { $0.id != excludeId }
        }
        let all = (try? await store.load(workspacePath: ws)) ?? []
        let (related, files) = RelatedAreaDetector.analyze(all)
        return ActiveWorkSnapshot(registrations: active, relatedAreas: related, fileOverlaps: files)
    }

    public func refreshRegistration(
        workspacePath: String,
        registrationId: UUID,
        task: String,
        branch: String?,
        worktree: String?
    ) async throws -> AgentRegistration {
        let ws = WorkspacePath.canonical(workspacePath)
        guard var reg = try await store.find(workspacePath: ws, id: registrationId) else {
            throw AwarenessError.registrationNotFound
        }
        guard reg.status.isOnBoard else {
            throw AwarenessError.registrationNotActive
        }

        let resolvedWorktree = worktree.map { WorkspacePath.canonical($0) } ?? reg.worktree
        let resolvedBranch = branch ?? detectBranch(worktree: resolvedWorktree) ?? reg.branch
        reg.branch = resolvedBranch
        reg.worktree = resolvedWorktree
        reg.lastSeen = Date()
        if task.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "observing" {
            reg.task = "observing"
            reg.status = .observing
        } else {
            reg.task = task
            reg.status = .active
        }

        try await store.upsert(workspacePath: ws, registration: reg)
        _ = await refreshGit(workspacePath: ws, registrationId: registrationId)
        return reg
    }

    public func update(workspacePath: String, registrationId: UUID, patch: UpdateAgentRequest) async throws -> AgentRegistration {
        let ws = WorkspacePath.canonical(workspacePath)
        guard var reg = try await store.find(workspacePath: ws, id: registrationId) else {
            throw AwarenessError.registrationNotFound
        }
        guard reg.status.isOnBoard else {
            throw AwarenessError.registrationNotActive
        }

        if let hypothesis = patch.hypothesis, !hypothesis.isEmpty {
            reg.hypothesis = hypothesis
        }
        reg.discoveredFacts.append(contentsOf: patch.discoveredFacts)
        reg.negatedHypotheses.append(contentsOf: patch.negatedHypotheses)
        reg.invariantsChanged.append(contentsOf: patch.invariantsChanged)
        reg.testsAdded.append(contentsOf: patch.testsAdded)
        reg.openQuestions.append(contentsOf: patch.openQuestions)
        reg.lastSeen = Date()
        reg.status = .active

        try await store.upsert(workspacePath: ws, registration: reg)
        try writeSummary(workspacePath: ws, registration: reg)
        return reg
    }

    public func markDone(workspacePath: String, registrationId: UUID) async throws -> AgentRegistration {
        let ws = WorkspacePath.canonical(workspacePath)
        guard var reg = try await store.find(workspacePath: ws, id: registrationId) else {
            throw AwarenessError.registrationNotFound
        }
        reg.status = .done
        reg.completedAt = Date()
        reg.lastSeen = Date()
        try await store.upsert(workspacePath: ws, registration: reg)
        try writeSummary(workspacePath: ws, registration: reg, final: true)
        return reg
    }

    @discardableResult
    public func refreshGit(workspacePath: String, registrationId: UUID) async -> AgentRegistration? {
        let ws = WorkspacePath.canonical(workspacePath)
        do {
            guard var reg = try await store.find(workspacePath: ws, id: registrationId),
                  reg.status.isOnBoard else { return nil }

            guard let obs = GitObserver.observe(worktreePath: reg.worktree) else {
                Self.logger.warning("git observe returned nil for \(reg.worktree, privacy: .public)")
                return reg
            }
            reg.branch = obs.branch
            reg.headSHA = obs.headSHA
            reg.changedFiles = obs.changedFiles
            reg.lastSeen = Date()
            try await store.upsert(workspacePath: ws, registration: reg)
            return reg
        } catch {
            Self.logger.warning("refreshGit failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private struct GitRefreshOutcome {
        var allSucceeded: Bool
        var failedCount: Int
    }

    private func refreshGitForWorkspace(_ workspacePath: String) async -> GitRefreshOutcome {
        let ws = WorkspacePath.canonical(workspacePath)
        let active: [AgentRegistration]
        do {
            active = try await store.activeRegistrations(workspacePath: ws)
        } catch {
            Self.logger.warning("refreshGitForWorkspace load failed: \(error.localizedDescription, privacy: .public)")
            return GitRefreshOutcome(allSucceeded: false, failedCount: 1)
        }

        var failed = 0
        for reg in active {
            let before = reg.headSHA
            let after = await refreshGit(workspacePath: ws, registrationId: reg.id)
            if after == nil && before == nil && !reg.changedFiles.isEmpty {
                // no-op
            } else if after == nil {
                failed += 1
            }
        }
        return GitRefreshOutcome(allSucceeded: failed == 0, failedCount: failed)
    }

    public func pollGitForKnownWorkspaces() async {
        let workspaces = await WorkspaceRegistry.shared.all()
        for workspacePath in workspaces {
            _ = await refreshGitForWorkspace(workspacePath)
        }
    }

    private func refreshPresenceStatus(workspacePath: String) async {
        let ws = WorkspacePath.canonical(workspacePath)
        do {
            var all = try await store.load(workspacePath: ws)
            let now = Date()
            var changed = false
            for idx in all.indices where all[idx].status.isOnBoard && all[idx].status != .observing {
                let elapsed = now.timeIntervalSince(all[idx].lastSeen)
                let newStatus: AgentRegistrationStatus
                if elapsed <= activeInterval {
                    newStatus = .active
                } else if elapsed <= idleInterval {
                    newStatus = .idle
                } else {
                    newStatus = .stale
                }
                if all[idx].status != newStatus {
                    all[idx].status = newStatus
                    changed = true
                }
            }
            if changed {
                try await store.save(workspacePath: ws, registrations: all)
            }
        } catch {
            Self.logger.warning("refreshPresenceStatus failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func detectBranch(worktree: String) -> String? {
        GitObserver.observe(worktreePath: worktree)?.branch
    }

    private func writeSummary(workspacePath: String, registration: AgentRegistration, final: Bool = false) throws {
        let safeBranch = registration.branch.replacingOccurrences(of: "/", with: "_")
        let dir = URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".blaze/radar/\(safeBranch)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var lines: [String] = []
        lines.append("# Branch Summary: \(registration.branch)")
        lines.append("")
        lines.append("Agent: \(registration.agentName)")
        lines.append("Task: \(registration.task)")
        if final { lines.append("Status: done") }
        lines.append("")
        if let hypothesis = registration.hypothesis, !hypothesis.isEmpty {
            lines.append("## Hypothesis")
            lines.append(hypothesis)
            lines.append("")
        }
        if !registration.negatedHypotheses.isEmpty {
            lines.append("## Ruled Out")
            for item in registration.negatedHypotheses { lines.append("- \(item)") }
            lines.append("")
        }
        if !registration.discoveredFacts.isEmpty {
            lines.append("## Learned")
            for item in registration.discoveredFacts { lines.append("- \(item)") }
            lines.append("")
        }
        if !registration.invariantsChanged.isEmpty {
            lines.append("## Invariants Changed")
            for item in registration.invariantsChanged { lines.append("- \(item)") }
            lines.append("")
        }
        if !registration.testsAdded.isEmpty {
            lines.append("## Tests")
            for item in registration.testsAdded { lines.append("- \(item)") }
            lines.append("")
        }
        if !registration.changedFiles.isEmpty {
            lines.append("## Files")
            for item in registration.changedFiles { lines.append("- \(item)") }
            lines.append("")
        }

        let summaryURL = dir.appendingPathComponent("summary.md")
        try lines.joined(separator: "\n").write(to: summaryURL, atomically: true, encoding: .utf8)
    }
}

/// Background git observation loop for registered worktrees.
public final class AwarenessGitPoller: @unchecked Sendable {
    private let service: AwarenessService
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "dev.blazeradar.git-poller")

    public init(service: AwarenessService, interval: TimeInterval = 30) {
        self.service = service
        self.interval = interval
    }

    public func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.pollKnownWorkspaces() }
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    private func pollKnownWorkspaces() async {
        await service.pollGitForKnownWorkspaces()
    }
}
