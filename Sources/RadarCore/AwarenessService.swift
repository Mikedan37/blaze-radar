import Foundation

public actor AwarenessService {
    private let store: AwarenessStore
    private let staleInterval: TimeInterval = 30 * 60

    public init(store: AwarenessStore = AwarenessStore()) {
        self.store = store
    }

    public func register(
        workspacePath: String,
        agentName: String,
        task: String,
        branch: String?,
        worktree: String?
    ) async throws -> AgentRegistration {
        let resolvedWorktree = worktree ?? workspacePath
        let resolvedBranch = branch ?? detectBranch(worktree: resolvedWorktree) ?? "unknown"

        let registration = AgentRegistration(
            agentName: agentName,
            task: task,
            branch: resolvedBranch,
            worktree: resolvedWorktree
        )

        try await store.upsert(workspacePath: workspacePath, registration: registration)
        await WorkspaceRegistry.shared.note(workspacePath)
        _ = await refreshGit(workspacePath: workspacePath, registrationId: registration.id)
        return registration
    }

    public func sync(workspacePath: String, registrationId: UUID?) async -> ActiveWorkSnapshot {
        await WorkspaceRegistry.shared.note(workspacePath)
        await refreshGitForWorkspace(workspacePath)
        if let registrationId,
           var reg = await store.find(workspacePath: workspacePath, id: registrationId),
           reg.status == .active {
            reg.lastSeen = Date()
            try? await store.upsert(workspacePath: workspacePath, registration: reg)
        }
        return await getActiveWork(workspacePath: workspacePath, excludeId: nil)
    }

    public func getActiveWork(workspacePath: String, excludeId: UUID? = nil) async -> ActiveWorkSnapshot {
        await reapStale(workspacePath: workspacePath)
        var active = await store.activeRegistrations(workspacePath: workspacePath)
        if let excludeId {
            active = active.filter { $0.id != excludeId }
        }
        let (related, files) = RelatedAreaDetector.analyze(await store.load(workspacePath: workspacePath))
        return ActiveWorkSnapshot(registrations: active, relatedAreas: related, fileOverlaps: files)
    }

    public func update(workspacePath: String, registrationId: UUID, patch: UpdateAgentRequest) async throws -> AgentRegistration {
        guard var reg = await store.find(workspacePath: workspacePath, id: registrationId) else {
            throw AwarenessError.registrationNotFound
        }
        guard reg.status == .active else {
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

        try await store.upsert(workspacePath: workspacePath, registration: reg)
        try writeSummary(workspacePath: workspacePath, registration: reg)
        return reg
    }

    public func markDone(workspacePath: String, registrationId: UUID) async throws -> AgentRegistration {
        guard var reg = await store.find(workspacePath: workspacePath, id: registrationId) else {
            throw AwarenessError.registrationNotFound
        }
        reg.status = .done
        reg.completedAt = Date()
        reg.lastSeen = Date()
        try await store.upsert(workspacePath: workspacePath, registration: reg)
        try writeSummary(workspacePath: workspacePath, registration: reg, final: true)
        return reg
    }

    public func refreshGit(workspacePath: String, registrationId: UUID) async -> AgentRegistration? {
        guard var reg = await store.find(workspacePath: workspacePath, id: registrationId),
              reg.status == .active else { return nil }

        if let obs = GitObserver.observe(worktreePath: reg.worktree) {
            reg.branch = obs.branch
            reg.headSHA = obs.headSHA
            reg.changedFiles = obs.changedFiles
            reg.lastSeen = Date()
            try? await store.upsert(workspacePath: workspacePath, registration: reg)
        }
        return reg
    }

    public func refreshGitForWorkspace(_ workspacePath: String) async {
        let active = await store.activeRegistrations(workspacePath: workspacePath)
        for reg in active {
            _ = await refreshGit(workspacePath: workspacePath, registrationId: reg.id)
        }
    }

    private func reapStale(workspacePath: String) async {
        var all = await store.load(workspacePath: workspacePath)
        let now = Date()
        var changed = false
        for idx in all.indices where all[idx].status == .active {
            if now.timeIntervalSince(all[idx].lastSeen) > staleInterval {
                all[idx].status = .withdrawn
                changed = true
            }
        }
        if changed {
            try? await store.save(workspacePath: workspacePath, registrations: all)
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
        let workspaces = await WorkspaceRegistry.shared.all()
        for workspacePath in workspaces {
            await service.refreshGitForWorkspace(workspacePath)
        }
    }
}
