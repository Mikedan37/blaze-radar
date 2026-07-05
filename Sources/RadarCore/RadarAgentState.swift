import Foundation

/// Per-agent CLI state — lives outside the repo. Workspace owns the board; agents own identity + sync cursor.
public enum RadarAgentState {
    public struct SessionFile: Codable, Equatable {
        public var agentId: String
        public var name: String
        public var workspace: String
        public var createdAt: Date
        public var lastSeen: Date

        public init(agentId: String, name: String, workspace: String, createdAt: Date = Date(), lastSeen: Date = Date()) {
            self.agentId = agentId
            self.name = name
            self.workspace = workspace
            self.createdAt = createdAt
            self.lastSeen = lastSeen
        }
    }

    public struct RegistrationSnapshot: Codable, Equatable {
        public var discoveredFacts: [String]
        public var negatedHypotheses: [String]
        public var hypothesis: String?
        public var invariantsChanged: [String]
        public var testsAdded: [String]
        public var openQuestions: [String]
        public var changedFiles: [String]
        public var status: String
    }

    public struct SyncFile: Codable {
        public var syncedAt: Date
        public var registrations: [String: RegistrationSnapshot]
    }

    private static var homeDirectory: String {
        if let envHome = ProcessInfo.processInfo.environment["HOME"], !envHome.isEmpty {
            return (envHome as NSString).standardizingPath
        }
        return NSHomeDirectory()
    }

    private static var root: URL {
        URL(fileURLWithPath: homeDirectory).appendingPathComponent(".blaze/radar", isDirectory: true)
    }

    public static func workspaceHash(_ workspacePath: String) -> String {
        RepositoryIdentity.workspaceHash(from: workspacePath)
    }

    public static func agentDirectory(workspacePath: String, agentId: String) -> URL {
        let hash = workspaceHash(workspacePath)
        return root
            .appendingPathComponent("workspaces/\(hash)/agents/\(agentId)", isDirectory: true)
    }

    private static func nameIndexURL(workspacePath: String) -> URL {
        let hash = workspaceHash(workspacePath)
        return root.appendingPathComponent("workspaces/\(hash)/by-name.json")
    }

    private static func defaultAgentURL(workspacePath: String) -> URL {
        let hash = workspaceHash(workspacePath)
        return root.appendingPathComponent("workspaces/\(hash)/default-agent.txt")
    }

    public static func resolveAgentName(workspacePath: String, explicit: String?) -> String {
        let normalized = (workspacePath as NSString).standardizingPath
        if let explicit, !explicit.isEmpty {
            return explicit
        }
        let url = defaultAgentURL(workspacePath: normalized)
        if let existing = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let generated = generateAgentName()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? generated.write(to: url, atomically: true, encoding: .utf8)
        return generated
    }

    public static func generateAgentName() -> String {
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).lowercased()
        return "agent-\(suffix)"
    }

    public static func findSession(workspacePath: String, agentName: String) -> SessionFile? {
        let normalized = (workspacePath as NSString).standardizingPath
        guard let agentId = loadNameIndex(workspacePath: normalized)[agentName],
              let session = loadSession(workspacePath: normalized, agentId: agentId),
              session.name == agentName else {
            return nil
        }
        return session
    }

    public static func loadSession(workspacePath: String, agentId: String) -> SessionFile? {
        let url = agentDirectory(workspacePath: workspacePath, agentId: agentId)
            .appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionFile.self, from: data)
    }

    @discardableResult
    public static func saveSession(_ session: SessionFile) throws -> URL {
        let dir = agentDirectory(workspacePath: session.workspace, agentId: session.agentId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("session.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(session).write(to: url, options: .atomic)
        try updateNameIndex(workspacePath: session.workspace, agentName: session.name, agentId: session.agentId)
        return url
    }

    public static func touchSession(workspacePath: String, agentName: String) throws {
        guard var session = findSession(workspacePath: workspacePath, agentName: agentName) else { return }
        session.lastSeen = Date()
        try saveSession(session)
    }

    public static func clearSession(workspacePath: String, agentName: String) {
        let normalized = (workspacePath as NSString).standardizingPath
        guard let agentId = loadNameIndex(workspacePath: normalized)[agentName] else { return }
        let dir = agentDirectory(workspacePath: normalized, agentId: agentId)
        try? FileManager.default.removeItem(at: dir)
        var index = loadNameIndex(workspacePath: normalized)
        index.removeValue(forKey: agentName)
        persistNameIndex(workspacePath: normalized, index: index)
    }

    public static func loadSync(workspacePath: String, agentId: String) -> SyncFile? {
        let url = agentDirectory(workspacePath: workspacePath, agentId: agentId)
            .appendingPathComponent("sync.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SyncFile.self, from: data)
    }

    public static func saveSync(workspacePath: String, agentId: String, snapshot: ActiveWorkSnapshot) throws {
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
        let file = SyncFile(syncedAt: Date(), registrations: registrations)
        let dir = agentDirectory(workspacePath: workspacePath, agentId: agentId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("sync.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    public static func clearSync(workspacePath: String, agentId: String) {
        let url = agentDirectory(workspacePath: workspacePath, agentId: agentId)
            .appendingPathComponent("sync.json")
        try? FileManager.default.removeItem(at: url)
    }

    public static func formatDelta(
        current: ActiveWorkSnapshot,
        previous: SyncFile?,
        excludeRegistrationId: String?
    ) -> String {
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
                appendNew(&lines, "Ruled out", reg.negatedHypotheses.map { "NOT: \($0)" }, prefix: "+ ")
                if let hypothesis = reg.hypothesis, !hypothesis.isEmpty {
                    lines.append("  Hypothesis:")
                    lines.append("    + \(hypothesis)")
                }
                continue
            }

            var agentLines: [String] = []
            appendNew(&agentLines, "Found", reg.discoveredFacts, previous: old!.discoveredFacts, prefix: "+ ")
            appendNew(&agentLines, "Ruled out", reg.negatedHypotheses.map { "NOT: \($0)" }, previous: old!.negatedHypotheses.map { "NOT: \($0)" }, prefix: "+ ")
            appendNew(&agentLines, "Changed", reg.invariantsChanged, previous: old!.invariantsChanged, prefix: "+ ")
            appendNew(&agentLines, "Tests", reg.testsAdded, previous: old!.testsAdded, prefix: "+ ")
            appendNew(&agentLines, "Questions", reg.openQuestions, previous: old!.openQuestions, prefix: "+ ")
            appendNew(&agentLines, "Files", reg.changedFiles, previous: old!.changedFiles, prefix: "+ ")

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

    private static func appendNew(
        _ lines: inout [String],
        _ label: String,
        _ items: [String],
        previous: [String] = [],
        prefix: String
    ) {
        let newItems = items.filter { !previous.contains($0) }
        guard !newItems.isEmpty else { return }
        lines.append("  \(label):")
        for item in newItems { lines.append("    \(prefix)\(item)") }
    }

    private static func loadNameIndex(workspacePath: String) -> [String: String] {
        let url = nameIndexURL(workspacePath: workspacePath)
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return index
    }

    private static func updateNameIndex(workspacePath: String, agentName: String, agentId: String) throws {
        var index = loadNameIndex(workspacePath: workspacePath)
        index[agentName] = agentId
        persistNameIndex(workspacePath: workspacePath, index: index)
    }

    private static func persistNameIndex(workspacePath: String, index: [String: String]) {
        let url = nameIndexURL(workspacePath: workspacePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
