import Foundation

/// Tracks awareness workspace roots so the git poller polls registered worktrees.
public actor WorkspaceRegistry {
    public static let shared = WorkspaceRegistry()

    private struct Persisted: Codable {
        var workspaces: [String]
    }

    private let fileManager: FileManager
    private let persistURL: URL
    private var workspaces: Set<String> = []

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        persistURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".blaze/daemon/radar-workspaces.json")
        workspaces = Self.loadPersisted(from: persistURL)
    }

    public func note(_ workspacePath: String) {
        let normalized = (workspacePath as NSString).standardizingPath
        guard workspaces.insert(normalized).inserted else { return }
        persist()
    }

    public func all() -> [String] {
        Array(workspaces).sorted()
    }

    private func persist() {
        let dir = persistURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = Persisted(workspaces: Array(workspaces).sorted())
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: persistURL, options: .atomic)
    }

    private static func loadPersisted(from url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(Persisted.self, from: data) else {
            return []
        }
        return Set(state.workspaces.map { ($0 as NSString).standardizingPath })
    }
}
