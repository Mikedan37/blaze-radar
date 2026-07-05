import Foundation

struct GitObservation {
    let branch: String
    let headSHA: String
    let changedFiles: [String]
}

enum GitObserver {
    static func observe(worktreePath: String) -> GitObservation? {
        guard FileManager.default.fileExists(atPath: worktreePath) else { return nil }

        let branch = shell("/usr/bin/git", ["-C", worktreePath, "branch", "--show-current"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head = shell("/usr/bin/git", ["-C", worktreePath, "rev-parse", "HEAD"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !branch.isEmpty, !head.isEmpty else { return nil }

        var files = Set<String>()

        let diff = shell("/usr/bin/git", ["-C", worktreePath, "diff", "--name-only", "HEAD"])
        for line in diff.output.split(separator: "\n") where !line.isEmpty {
            files.insert(String(line))
        }

        let status = shell("/usr/bin/git", ["-C", worktreePath, "status", "--porcelain"])
        for line in status.output.split(separator: "\n") where !line.isEmpty {
            let trimmed = String(line)
            if trimmed.hasPrefix("?? ") {
                files.insert(String(trimmed.dropFirst(3)))
            } else if trimmed.count > 3 {
                files.insert(String(trimmed.dropFirst(3)))
            }
        }

        let relevant = RadarCoordinationPaths.coordinationRelevant(files.sorted())
        return GitObservation(branch: branch, headSHA: head, changedFiles: relevant)
    }

    private static func shell(_ cmd: String, _ args: [String]) -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
        } catch {
            return ("", -1)
        }
    }
}
