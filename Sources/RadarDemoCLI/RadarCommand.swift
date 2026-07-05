import ArgumentParser
import Foundation
import RadarDemoClient
import RadarCore

@main
struct RadarDemoCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blaze-radar-demo",
        abstract: "Demo CLI for Blaze Radar (canonical path: AgentDaemon + AgentCLI)",
        subcommands: [RadarCommand.self]
    )
}

enum RadarClientFactory {
    static func make() -> RadarDaemonClient { RadarDaemonClient() }
}

struct RadarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "radar",
        abstract: "Observe parallel agent work",
        subcommands: [
            RadarSyncCommand.self,
            RadarNoteCommand.self,
            RadarDoneCommand.self,
            RadarStatusCommand.self,
            // Legacy demo commands — prefer sync/note above
            RadarRegisterCommand.self,
            RadarActiveCommand.self,
            RadarUpdateCommand.self,
        ]
    )
}

private func shortId(_ id: String) -> String { String(id.prefix(6)) }

struct RadarRegisterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "register",
        abstract: "Register this agent's work",
        shouldDisplay: false
    )

    @Argument(help: "What you are trying to solve") var task: String
    @Option(name: .long, help: "Agent name (auto-generated per workspace if omitted)") var agent: String?
    @Option(name: .long, help: "Git branch") var branch: String?
    @Option(name: .long, help: "Git worktree path") var worktree: String?
    @Option(name: .long, help: "Workspace path") var workspace: String = "."
    @Flag(name: .long, help: "Force a new registration") var new: Bool = false

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        let wsPath = workspaceURL.path
        let agentName = RadarAgentState.resolveAgentName(workspacePath: wsPath, explicit: agent)
        let worktreePath = worktree ?? workspaceURL.path
        if let worktree, !FileManager.default.fileExists(atPath: worktree) {
            fputs("Worktree not found: \(worktree)\n", stderr)
            throw ExitCode.failure
        }

        if !new, let existing = RadarAgentState.findSession(workspacePath: wsPath, agentName: agentName) {
            let client = RadarClientFactory.make()
            defer { client.disconnect() }
            let snapshot = try await client.getActiveWork(workspacePath: wsPath)
            if snapshot.registrations.contains(where: { $0.id.uuidString == existing.agentId }) {
                _ = try await client.refreshRegistration(
                    workspacePath: wsPath,
                    registrationId: existing.agentId,
                    task: task,
                    branch: branch,
                    worktree: worktreePath
                )
                try RadarAgentState.touchSession(workspacePath: wsPath, agentName: agentName)
                print("Resumed \(agentName)-\(shortId(existing.agentId))")
                print("  task: \(task)")
                return
            }
        }

        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        let response = try await client.registerAgent(
            workspacePath: wsPath, agentName: agentName, task: task, branch: branch, worktree: worktreePath
        )
        try RadarAgentState.saveSession(RadarAgentState.SessionFile(
            agentId: response.registrationId, name: agentName, workspace: wsPath
        ))
        print("Created \(agentName)-\(shortId(response.registrationId))")
        print("  branch: \(response.branch)")
    }
}

struct RadarActiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "active",
        abstract: "Show active agent work",
        shouldDisplay: false
    )

    @Option(name: .long, help: "Workspace path") var workspace: String = "."
    @Flag(name: .long, help: "Output JSON") var json: Bool = false

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        let snapshot = try await client.getActiveWork(workspacePath: workspaceURL.path)
        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            print(String(data: try encoder.encode(snapshot), encoding: .utf8) ?? "{}")
            return
        }
        print(RadarFormatter.formatSnapshot(snapshot))
    }
}

struct RadarSyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Checkpoint: heartbeat, git refresh, new findings since last sync"
    )

    @Option(name: .long, help: "Agent name (auto-generated per workspace if omitted)") var agent: String?
    @Option(name: .long, help: "Task for auto-registration when no session exists") var task: String = "observing"
    @Option(name: .long, help: "Workspace path") var workspace: String = "."
    @Flag(name: .long, help: "Output JSON") var json: Bool = false

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        let wsPath = workspaceURL.path
        let agentName = RadarAgentState.resolveAgentName(workspacePath: wsPath, explicit: agent)

        var autoRegistered = false
        var session = RadarAgentState.findSession(workspacePath: wsPath, agentName: agentName)
        if session == nil {
            let client = RadarClientFactory.make()
            defer { client.disconnect() }
            let response = try await client.registerAgent(
                workspacePath: wsPath, agentName: agentName, task: task, worktree: wsPath
            )
            session = RadarAgentState.SessionFile(agentId: response.registrationId, name: agentName, workspace: wsPath)
            try RadarAgentState.saveSession(session!)
            print("No radar identity found.")
            print("Created \(agentName)-\(shortId(response.registrationId))")
            print("✓ registered")
            autoRegistered = true
        }
        guard let session else { throw ExitCode.failure }

        let previous = RadarAgentState.loadSync(workspacePath: wsPath, agentId: session.agentId)
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        let result = try await client.syncRadar(workspacePath: wsPath, registrationId: session.agentId)
        try RadarAgentState.touchSession(workspacePath: wsPath, agentName: agentName)

        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            print(String(data: try encoder.encode(result.snapshot), encoding: .utf8) ?? "{}")
            try RadarAgentState.saveSync(workspacePath: wsPath, agentId: session.agentId, snapshot: result.snapshot)
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        print("SYNC @ \(formatter.string(from: Date()))")
        for line in result.formatStatusLines() { print(line) }
        if autoRegistered { print("✓ synced") }
        print("")
        print("NEW since last sync:")
        print(RadarAgentState.formatDelta(
            current: result.snapshot, previous: previous, excludeRegistrationId: session.agentId
        ))
        print("")
        print("---")
        print("")
        print(RadarFormatter.formatSnapshot(result.snapshot))
        try RadarAgentState.saveSync(workspacePath: wsPath, agentId: session.agentId, snapshot: result.snapshot)
    }
}

struct RadarNoteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "note", abstract: "Add a note to the board")

    @Argument(help: "Note text") var text: String
    @Option(name: .long, help: "Agent name (auto-generated per workspace if omitted)") var agent: String?
    @Option(name: .long, help: "Workspace path") var workspace: String = "."

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        let wsPath = workspaceURL.path
        let agentName = RadarAgentState.resolveAgentName(workspacePath: wsPath, explicit: agent)
        guard let session = RadarAgentState.findSession(workspacePath: wsPath, agentName: agentName) else {
            fputs("No radar session — run: blaze-radar-demo radar sync\n", stderr)
            throw ExitCode.failure
        }
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        try await client.updateAgent(UpdateAgentRequest(
            workspacePath: wsPath,
            registrationId: session.agentId,
            discoveredFacts: [text]
        ))
        try RadarAgentState.touchSession(workspacePath: wsPath, agentName: agentName)
        print("Note added")
    }
}

struct RadarStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Peek at the board without heartbeat")

    @Option(name: .long, help: "Workspace path") var workspace: String = "."
    @Flag(name: .long, help: "Output JSON") var json: Bool = false

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        let snapshot = try await client.getActiveWork(workspacePath: workspaceURL.path)
        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            print(String(data: try encoder.encode(snapshot), encoding: .utf8) ?? "{}")
            return
        }
        print(RadarFormatter.formatSnapshot(snapshot))
    }
}

struct RadarUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Record mid-investigation learnings",
        shouldDisplay: false
    )

    @Option(name: .long, help: "Agent name (auto-generated per workspace if omitted)") var agent: String?
    @Option(name: .long) var hypothesis: String?
    @Option(name: .long) var found: [String] = []
    @Option(name: .long) var ruledOut: [String] = []
    @Option(name: .long) var invariant: [String] = []
    @Option(name: .long) var test: [String] = []
    @Option(name: .long) var question: [String] = []
    @Option(name: .long) var workspace: String = "."

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        let wsPath = workspaceURL.path
        let agentName = RadarAgentState.resolveAgentName(workspacePath: wsPath, explicit: agent)
        guard let session = RadarAgentState.findSession(workspacePath: wsPath, agentName: agentName) else {
            fputs("No radar session — run: blaze-radar-demo radar sync (auto-registers)\n", stderr)
            throw ExitCode.failure
        }
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        try await client.updateAgent(UpdateAgentRequest(
            workspacePath: wsPath,
            registrationId: session.agentId,
            hypothesis: hypothesis,
            discoveredFacts: found,
            negatedHypotheses: ruledOut,
            invariantsChanged: invariant,
            testsAdded: test,
            openQuestions: question
        ))
        try RadarAgentState.touchSession(workspacePath: wsPath, agentName: agentName)
        print("Updated radar notes")
    }
}

struct RadarDoneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "done", abstract: "Finalize this agent's registration")

    @Option(name: .long, help: "Agent name (auto-generated per workspace if omitted)") var agent: String?
    @Option(name: .long) var workspace: String = "."

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        let wsPath = workspaceURL.path
        let agentName = RadarAgentState.resolveAgentName(workspacePath: wsPath, explicit: agent)
        guard let session = RadarAgentState.findSession(workspacePath: wsPath, agentName: agentName) else {
            fputs("No radar session — run: blaze-radar-demo radar sync (auto-registers)\n", stderr)
            throw ExitCode.failure
        }
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        try await client.markDone(workspacePath: wsPath, registrationId: session.agentId)
        RadarAgentState.clearSession(workspacePath: wsPath, agentName: agentName)
        RadarAgentState.clearSync(workspacePath: wsPath, agentId: session.agentId)
        print("Marked done — off active board, notes kept")
    }
}

enum RadarFormatter {
    static func formatSnapshot(_ snapshot: ActiveWorkSnapshot) -> String {
        var lines = ["ACTIVE"]
        if snapshot.registrations.isEmpty {
            lines.append("")
            lines.append("(no active work)")
            return lines.joined(separator: "\n")
        }
        for reg in snapshot.registrations {
            lines.append("")
            let statusSuffix = reg.status == .active ? "" : " [\(reg.status.rawValue)]"
            lines.append("\(reg.agentName)\(statusSuffix)")
            lines.append("  Branch: \(reg.branch)")
            lines.append("  Goal:")
            lines.append("    \(reg.task)")
            if let hypothesis = reg.hypothesis, !hypothesis.isEmpty {
                lines.append("  Hypothesis:")
                lines.append("    \(hypothesis)")
            }
            let learned = reg.discoveredFacts + reg.negatedHypotheses.map { "NOT: \($0)" }
            if !learned.isEmpty {
                lines.append("  Learned:")
                learned.forEach { lines.append("    \($0)") }
            }
            if !reg.changedFiles.isEmpty {
                lines.append("  Files:")
                reg.changedFiles.forEach { lines.append("    \($0)") }
            }
        }
        for warning in snapshot.relatedAreas {
            lines.append("")
            lines.append("⚠ Related area:")
            lines.append("  \(warning.branches.joined(separator: " + "))")
            lines.append("  \(warning.reason)")
        }
        for overlap in snapshot.fileOverlaps {
            lines.append("")
            lines.append("⚠ File overlap:")
            lines.append("  \(overlap.path) — \(overlap.agentNames.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}
