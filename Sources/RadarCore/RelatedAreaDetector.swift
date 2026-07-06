import Foundation

/// Dumb overlap checks — agents have the brains, Radar does not.
public enum RelatedAreaDetector {
    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "to", "of", "in", "on", "for", "is", "are", "was", "were",
        "be", "been", "being", "fix", "fixing", "found", "not", "don", "t", "it", "its", "this",
        "that", "with", "from", "at", "by", "as", "into", "after", "before", "another", "build",
    ]

    public static func analyze(_ registrations: [AgentRegistration]) -> (related: [RelatedAreaWarning], files: [FileOverlapWarning]) {
        let active = registrations.filter { $0.status.collisionRelevant }
        var related: [RelatedAreaWarning] = []
        var files: [FileOverlapWarning] = []

        for i in 0..<active.count {
            for j in (i + 1)..<active.count {
                let a = active[i]
                let b = active[j]
                if let reason = relatedReason(a, b) {
                    related.append(RelatedAreaWarning(
                        agentNames: [a.agentName, b.agentName],
                        branches: [a.branch, b.branch],
                        reason: reason
                    ))
                }
            }
        }

        var fileToAgents: [String: [(name: String, branch: String)]] = [:]
        for reg in active {
            for path in RadarCoordinationPaths.coordinationRelevant(reg.changedFiles) {
                fileToAgents[path, default: []].append((reg.agentName, reg.branch))
            }
        }
        for (path, agents) in fileToAgents where agents.count > 1 {
            files.append(FileOverlapWarning(
                path: path,
                agentNames: agents.map(\.name),
                branches: agents.map(\.branch)
            ))
        }

        return (related, files)
    }

    private static func relatedReason(_ a: AgentRegistration, _ b: AgentRegistration) -> String? {
        if isDeclaredTask(a.task) && isDeclaredTask(b.task) {
            let wordsA = taskWords(a.task)
            let wordsB = taskWords(b.task)
            let sharedWords = wordsA.intersection(wordsB)
            if !sharedWords.isEmpty {
                return "Same task words: \(sharedWords.sorted().joined(separator: ", "))"
            }
        }

        let filesA = RadarCoordinationPaths.coordinationRelevant(a.changedFiles)
        let filesB = RadarCoordinationPaths.coordinationRelevant(b.changedFiles)
        let sameFiles = Set(filesA).intersection(Set(filesB))
        if !sameFiles.isEmpty {
            let sample = sameFiles.sorted().prefix(3).joined(separator: ", ")
            return "Same files: \(sample)"
        }

        if directoryOverlap(filesA, filesB) {
            return "Same directory"
        }

        return nil
    }

    private static func taskWords(_ task: String) -> Set<String> {
        tokenize(task)
    }

    private static func isDeclaredTask(_ task: String) -> Bool {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !trimmed.isEmpty && trimmed != "checking in"
    }

    public static func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let parts = lowered.split { !$0.isLetter && !$0.isNumber }
        return Set(parts.map(String.init).filter { $0.count >= 3 && !stopwords.contains($0) })
    }

    private static func directoryOverlap(_ aFiles: [String], _ bFiles: [String]) -> Bool {
        let dirsA = Set(aFiles.compactMap { topDirectory($0) })
        let dirsB = Set(bFiles.compactMap { topDirectory($0) })
        return !dirsA.intersection(dirsB).isEmpty
    }

    private static func topDirectory(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        guard let first = parts.first else { return nil }
        return String(first)
    }
}
