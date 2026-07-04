import Foundation

public enum RelatedAreaDetector {
    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "to", "of", "in", "on", "for", "is", "are", "was", "were",
        "be", "been", "being", "fix", "fixing", "found", "not", "don", "t", "it", "its", "this",
        "that", "with", "from", "at", "by", "as", "into", "after", "before", "another", "build",
    ]

    private static let signalWords: Set<String> = [
        "signup", "prompt", "overlay", "attention", "scheduler", "interrupt", "interruptions",
        "nudge", "conversion", "modal", "evidence", "arbiter", "timing", "competing",
    ]

    public static func analyze(_ registrations: [AgentRegistration]) -> (related: [RelatedAreaWarning], files: [FileOverlapWarning]) {
        let active = registrations.filter { $0.status == .active }
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

        var fileToAgents: [String: [(String, String)]] = [:]
        for reg in active {
            for path in reg.changedFiles {
                fileToAgents[path, default: []].append((reg.agentName, reg.branch))
            }
        }
        for (path, agents) in fileToAgents where agents.count > 1 {
            files.append(FileOverlapWarning(
                path: path,
                agentNames: agents.map(\.0),
                branches: agents.map(\.1)
            ))
        }

        return (related, files)
    }

    private static func relatedReason(_ a: AgentRegistration, _ b: AgentRegistration) -> String? {
        let tokensA = tokens(for: a)
        let tokensB = tokens(for: b)
        let common = tokensA.intersection(tokensB)

        if common.count >= 2 {
            return "Shared terms: \(common.sorted().prefix(4).joined(separator: ", "))"
        }

        let signalsA = signalHits(tokensA)
        let signalsB = signalHits(tokensB)
        let sharedSignals = signalsA.intersection(signalsB)
        if !sharedSignals.isEmpty {
            return "Both affect \(sharedSignals.sorted().joined(separator: " / ")) surfaces"
        }

        if signalsA.contains(where: { signupFamily.contains($0) }) &&
            signalsB.contains(where: { signupFamily.contains($0) }) {
            return "Both affect signup timing / conversion surfaces"
        }

        if pathPrefixOverlap(a.changedFiles, b.changedFiles) {
            return "Working in overlapping directories"
        }

        if !Set(a.changedFiles).intersection(Set(b.changedFiles)).isEmpty {
            return "Both modifying same files"
        }

        return nil
    }

    private static let signupFamily: Set<String> = [
        "signup", "prompt", "overlay", "attention", "interrupt", "interruptions",
        "nudge", "conversion", "modal", "evidence", "arbiter", "scheduler", "timing",
    ]

    public static func tokens(for registration: AgentRegistration) -> Set<String> {
        var text = registration.task
        if let hypothesis = registration.hypothesis { text += " " + hypothesis }
        text += " " + registration.discoveredFacts.joined(separator: " ")
        text += " " + registration.negatedHypotheses.joined(separator: " ")
        text += " " + registration.invariantsChanged.joined(separator: " ")
        return tokenize(text)
    }

    public static func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let parts = lowered.split { !$0.isLetter && !$0.isNumber }
        return Set(parts.map(String.init).filter { $0.count >= 3 && !stopwords.contains($0) })
    }

    private static func signalHits(_ tokens: Set<String>) -> Set<String> {
        tokens.intersection(signalWords)
    }

    private static func pathPrefixOverlap(_ aFiles: [String], _ bFiles: [String]) -> Bool {
        let prefixesA = Set(aFiles.compactMap { prefix($0) })
        let prefixesB = Set(bFiles.compactMap { prefix($0) })
        return !prefixesA.intersection(prefixesB).isEmpty
    }

    private static func prefix(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return parts.prefix(2).joined(separator: "/")
    }
}
