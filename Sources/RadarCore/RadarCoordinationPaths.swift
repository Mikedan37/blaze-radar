import Foundation

/// Paths that Radar install/bootstrap writes — not meaningful coordination conflicts.
public enum RadarCoordinationPaths {
    private static let infrastructureFiles: Set<String> = [
        "CLAUDE.md",
        "AGENTS.md",
        "GEMINI.md",
    ]

    public static func isInfrastructure(_ path: String) -> Bool {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if infrastructureFiles.contains(normalized) { return true }
        if normalized == ".blaze" || normalized.hasPrefix(".blaze/") { return true }
        return false
    }

    /// Changed files that matter for overlap / related-area warnings.
    public static func coordinationRelevant(_ paths: [String]) -> [String] {
        paths.filter { !isInfrastructure($0) }
    }

    public static func shareWorktree(_ a: AgentRegistration, _ b: AgentRegistration) -> Bool {
        WorkspacePath.canonical(a.worktree) == WorkspacePath.canonical(b.worktree)
    }
}
