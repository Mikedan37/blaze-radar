import ArgumentParser
import Foundation
import RadarClient
import RadarCore

@main
struct BlazeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blaze",
        abstract: "Blaze Radar — shared awareness for parallel coding agents",
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
            RadarRegisterCommand.self,
            RadarActiveCommand.self,
            RadarSyncCommand.self,
            RadarUpdateCommand.self,
            RadarDoneCommand.self,
        ]
    )
}

// MARK: - Session persistence

enum RadarSession {
    struct File: Codable {
        var registrationId: String
        var workspacePath: String
        var agentName: String
    }

    static func path(workspace: URL) -> URL {
        workspace.appendingPathComponent(".blaze/radar-session.json")
    }

    static func load(workspace: URL) -> File? {
        let url = path(workspace: workspace)
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return file
    }

    static func save(workspace: URL, registrationId: String, agentName: String) throws {
        let file = File(registrationId: registrationId, workspacePath: workspace.path, agentName: agentName)
        let url = path(workspace: workspace)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(file).write(to: url, options: .atomic)
    }

    static func clear(workspace: URL) {
        try? FileManager.default.removeItem(at: path(workspace: workspace))
    }
}

// MARK: - Sync state

enum RadarSyncState {
    struct RegistrationSnapshot: Codable, Equatable {
        var discoveredFacts: [String]
        var negatedHypotheses: [String]
        var hypothesis: String?
        var invariantsChanged: [String]
        var testsAdded: [String]
        var openQuestions: [String]
        var changedFiles: [String]
        var status: String
    }

    struct File: Codable {
        var syncedAt: Date
        var registrations: [String: RegistrationSnapshot]
    }

    static func path(workspace: URL) -> URL { workspace.appendingPathComponent(".blaze/radar-sync.json") }

    static func load(workspace: URL) -> File? {
        guard let data = try? Data(contentsOf: path(workspace: workspace)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(File.self, from: data)
    }

    static func save(workspace: URL, snapshot: ActiveWorkSnapshot) throws {
        var registrations: [String: RegistrationSnapshot] = [:]
        for reg in snapshot.registrations {
            registrations[reg.id.uuidString] = RegistrationSnapshot(
                discoveredFacts: reg.discoveredFacts,
                negatedHypotheses: reg.negatedHypotheses,
                hypothesis: reg.hypothesis,
                invariantsChanged: reg.invariantsChanged,
                testsAdded: reg.testsAdded,
                openQuestions: reg.openQuestions,
                changedFiles: reg.changedFiles,
                status: reg.status.rawValue
            )
        }
        let file = File(syncedAt: Date(), registrations: registrations)
        let url = path(workspace: workspace)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    static func clear(workspace: URL) {
        try? FileManager.default.removeItem(at: path(workspace: workspace))
    }

    static func formatDelta(current: ActiveWorkSnapshot, previous: File?, excludeRegistrationId: String?) -> String {
        if previous == nil {
            return "(first sync — baseline captured; future syncs show only new findings)"
        }

        var lines: [String] = []
        var hasNew = false
        let prior = previous!.registrations

        for reg in current.registrations {
            if reg.id.uuidString == excludeRegistrationId { continue }
            let old = prior[reg.id.uuidString]

            if old == nil {
                hasNew = true
                lines.append("")
                lines.append("\(reg.agentName) (\(reg.branch)) — newly active")
                appendNew(&lines, "Found", reg.discoveredFacts, prefix: "+ ")
                continue
            }

            var agentLines: [String] = []
            appendNew(&agentLines, "Found", reg.discoveredFacts, previous: old!.discoveredFacts, prefix: "+ ")
            appendNew(&agentLines, "Ruled out", reg.negatedHypotheses.map { "NOT: \($0)" }, previous: old!.negatedHypotheses.map { "NOT: \($0)" }, prefix: "+ ")
            if let hypothesis = reg.hypothesis, hypothesis != old!.hypothesis, !hypothesis.isEmpty {
                agentLines.append("  Hypothesis:")
                agentLines.append("    + \(hypothesis)")
            }
            if !agentLines.isEmpty {
                hasNew = true
                lines.append("")
                lines.append("\(reg.agentName) (\(reg.branch))")
                lines.append(contentsOf: agentLines)
            }
        }

        if !hasNew { lines.append("(no new findings since last sync)") }
        return lines.joined(separator: "\n")
    }

    private static func appendNew(_ lines: inout [String], _ label: String, _ items: [String], previous: [String] = [], prefix: String) {
        let newItems = items.filter { !previous.contains($0) }
        guard !newItems.isEmpty else { return }
        lines.append("  \(label):")
        for item in newItems { lines.append("    \(prefix)\(item)") }
    }
}

// MARK: - Commands

struct RadarRegisterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "register", abstract: "Register this agent's work")

    @Argument(help: "What you are trying to solve") var task: String
    @Option(name: .long, help: "Agent name") var agent: String = ProcessInfo.processInfo.hostName
    @Option(name: .long, help: "Git branch") var branch: String?
    @Option(name: .long, help: "Git worktree path") var worktree: String?
    @Option(name: .long, help: "Workspace path") var workspace: String = "."

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        let worktreePath = worktree ?? workspaceURL.path
        if let worktree, !FileManager.default.fileExists(atPath: worktree) {
            fputs("Worktree not found: \(worktree)\n", stderr)
            throw ExitCode.failure
        }
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        let response = try await client.registerAgent(
            workspacePath: workspaceURL.path, agentName: agent, task: task, branch: branch, worktree: worktreePath
        )
        try RadarSession.save(workspace: workspaceURL, registrationId: response.registrationId, agentName: agent)
        print("Registered on branch \(response.branch)")
        print("  session: \(response.registrationId)")
    }
}

struct RadarActiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "active", abstract: "Show active agent work")

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

    @Option(name: .long, help: "Workspace path") var workspace: String = "."
    @Flag(name: .long, help: "Output JSON") var json: Bool = false

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        let session = RadarSession.load(workspace: workspaceURL)
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        let snapshot = try await client.syncRadar(workspacePath: workspaceURL.path, registrationId: session?.registrationId)

        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            print(String(data: try encoder.encode(snapshot), encoding: .utf8) ?? "{}")
            try RadarSyncState.save(workspace: workspaceURL, snapshot: snapshot)
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        print("SYNC @ \(formatter.string(from: Date()))")
        print("")
        print("NEW since last sync:")
        print(RadarSyncState.formatDelta(current: snapshot, previous: RadarSyncState.load(workspace: workspaceURL), excludeRegistrationId: session?.registrationId))
        print("")
        print("---")
        print("")
        print(RadarFormatter.formatSnapshot(snapshot))
        try RadarSyncState.save(workspace: workspaceURL, snapshot: snapshot)
    }
}

struct RadarUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Record mid-investigation learnings")

    @Option(name: .long) var hypothesis: String?
    @Option(name: .long) var found: [String] = []
    @Option(name: .long) var ruledOut: [String] = []
    @Option(name: .long) var invariant: [String] = []
    @Option(name: .long) var test: [String] = []
    @Option(name: .long) var question: [String] = []
    @Option(name: .long) var workspace: String = "."

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        guard let session = RadarSession.load(workspace: workspaceURL) else {
            fputs("No radar session — run: blaze radar register \"<task>\"\n", stderr)
            throw ExitCode.failure
        }
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        try await client.updateAgent(UpdateAgentRequest(
            workspacePath: workspaceURL.path,
            registrationId: session.registrationId,
            hypothesis: hypothesis,
            discoveredFacts: found,
            negatedHypotheses: ruledOut,
            invariantsChanged: invariant,
            testsAdded: test,
            openQuestions: question
        ))
        print("Updated radar notes")
    }
}

struct RadarDoneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "done", abstract: "Finalize this agent's registration")

    @Option(name: .long) var workspace: String = "."

    func run() async throws {
        let workspaceURL = try Workspace.resolve(workspace)
        guard let session = RadarSession.load(workspace: workspaceURL) else {
            fputs("No radar session — run: blaze radar register \"<task>\"\n", stderr)
            throw ExitCode.failure
        }
        let client = RadarClientFactory.make()
        defer { client.disconnect() }
        try await client.markDone(workspacePath: workspaceURL.path, registrationId: session.registrationId)
        RadarSession.clear(workspace: workspaceURL)
        RadarSyncState.clear(workspace: workspaceURL)
        print("Radar registration done")
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
            lines.append(reg.agentName)
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
