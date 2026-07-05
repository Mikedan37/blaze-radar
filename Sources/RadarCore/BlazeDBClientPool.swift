import Foundation
import BlazeDB

/// One BlazeDB client per workspace — BlazeDB is single-writer per file.
actor BlazeDBClientPool {
    static let shared = BlazeDBClientPool()
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
}
