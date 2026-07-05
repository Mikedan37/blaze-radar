import CryptoKit
import Foundation

/// Stable repository identity for Radar board storage.
///
/// Three separate axes:
/// - **Repository identity** (`boardKey`) — which shared board? Derived from `git rev-parse --git-common-dir`.
/// - **Agent/session identity** — which card? One per terminal tab (`RadarAgentState.sessionKey()`).
/// - **Card context** — worktree path, branch, task, notes on the agent registration.
///
/// Same repository → same board. Different agent session → different card. Worktree and branch are metadata.
public enum RepositoryIdentity {
    public static func boardKey(from checkoutPath: String) -> String {
        if let common = gitCommonDirectory(from: checkoutPath) {
            return WorkspacePath.canonical(common)
        }
        return WorkspacePath.canonical(checkoutPath)
    }

    /// Short hash for `~/.blaze/radar/workspaces/<hash>/` session and board paths.
    public static func workspaceHash(from checkoutPath: String) -> String {
        let digest = SHA256.hash(data: Data(boardKey(from: checkoutPath).utf8))
        return digest.prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    public static func databaseURL(from checkoutPath: String) -> URL {
        let key = boardKey(from: checkoutPath)
        let hash = workspaceHash(from: checkoutPath)
        let url = radarHome
            .appendingPathComponent("workspaces/\(hash)/radar.blazedb", isDirectory: false)
        migrateLegacyDatabaseIfNeeded(checkoutPath: checkoutPath, boardKey: key, destination: url)
        return url
    }

    static let password = "BlazeRadar123!"

    static var radarHome: URL {
        let home = ProcessInfo.processInfo.environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (home?.isEmpty == false) ? home! : NSHomeDirectory()
        return URL(fileURLWithPath: (resolved as NSString).standardizingPath)
            .appendingPathComponent(".blaze/radar", isDirectory: true)
    }

    static func gitCommonDirectory(from checkoutPath: String) -> String? {
        let canonical = WorkspacePath.canonical(checkoutPath)
        let common = runGit(["-C", canonical, "rev-parse", "--git-common-dir"])
        guard !common.isEmpty else { return nil }

        if common.hasPrefix("/") {
            return WorkspacePath.canonical(common)
        }

        let toplevel = runGit(["-C", canonical, "rev-parse", "--show-toplevel"])
        guard !toplevel.isEmpty else { return nil }
        return WorkspacePath.canonical((toplevel as NSString).appendingPathComponent(common))
    }

    private static func legacyDatabaseURLs(checkoutPath: String) -> [URL] {
        let canonical = WorkspacePath.canonical(checkoutPath)
        var urls: [URL] = [
            URL(fileURLWithPath: canonical).appendingPathComponent(".blaze/radar/radar.blazedb")
        ]
        let toplevel = runGit(["-C", canonical, "rev-parse", "--show-toplevel"])
        if !toplevel.isEmpty {
            let top = WorkspacePath.canonical(toplevel)
            if top != canonical {
                urls.append(URL(fileURLWithPath: top).appendingPathComponent(".blaze/radar/radar.blazedb"))
            }
        }
        return urls
    }

    private static func migrateLegacyDatabaseIfNeeded(
        checkoutPath: String,
        boardKey: String,
        destination: URL
    ) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { return }

        for legacy in legacyDatabaseURLs(checkoutPath: checkoutPath) where fm.fileExists(atPath: legacy.path) {
            do {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: legacy, to: destination)
                return
            } catch {
                continue
            }
        }
    }

    private static func runGit(_ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}
