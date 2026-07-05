import Foundation
import BlazeDB

/// One BlazeDB client per workspace — BlazeDB is single-writer per file.
public actor BlazeDBClientPool {
    public static let shared = BlazeDBClientPool()
    private var clients: [String: BlazeDBClient] = [:]

    func client(workspacePath: String) throws -> BlazeDBClient {
        let key = WorkspacePath.canonical(workspacePath)
        if let existing = clients[key] { return existing }
        let url = RadarDBPaths.databaseURL(workspacePath: key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let client = try BlazeDBClient(name: "radar", fileURL: url, password: RadarDBPaths.password)
        clients[key] = client
        return client
    }

    func reset() {
        clients.removeAll()
    }

    /// Close and drop the pooled client for a workspace (public for AgentDaemon planWork boundary).
    public func evict(workspacePath: String) async {
        let key = WorkspacePath.canonical(workspacePath)
        guard let client = clients.removeValue(forKey: key) else { return }
        try? client.close()
    }

    /// Close every pooled radar client before AgentKit opens agentkit.db.
    public func evictAll() async {
        let snapshot = clients
        clients.removeAll()
        for (_, client) in snapshot {
            try? client.close()
        }
    }
}
