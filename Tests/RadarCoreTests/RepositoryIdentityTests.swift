import XCTest
@testable import RadarCore

final class RepositoryIdentityTests: XCTestCase {
    private var tempDir: URL!
    private var tempHome: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-repo-id-\(UUID().uuidString)")
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-repo-home-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("HOME", tempHome.path, 1)
    }

    override func tearDown() {
        unsetenv("HOME")
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(at: tempHome)
        super.tearDown()
    }

    func testGitWorktreesShareOneBoard() async throws {
        let repoRoot = tempDir.appendingPathComponent("repo")
        let wtAuth = tempDir.appendingPathComponent("wt-auth")
        let wtUi = tempDir.appendingPathComponent("wt-ui")

        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        try runGit(["init"], in: repoRoot)
        try runGit(["config", "user.email", "radar@test.local"], in: repoRoot)
        try runGit(["config", "user.name", "Radar Test"], in: repoRoot)
        try "hello".write(to: repoRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoRoot)
        try runGit(["commit", "-m", "init"], in: repoRoot)
        try runGit(["branch", "-m", "main"], in: repoRoot)
        try runGit(["worktree", "add", wtAuth.path, "-b", "fix-auth"], in: repoRoot)
        try runGit(["worktree", "add", wtUi.path, "-b", "fix-ui"], in: repoRoot)

        let keyAuth = RepositoryIdentity.boardKey(from: wtAuth.path)
        let keyUi = RepositoryIdentity.boardKey(from: wtUi.path)
        XCTAssertEqual(keyAuth, keyUi)

        let service = AwarenessService(store: BlazeDBAwarenessStore())
        _ = try await service.register(
            workspacePath: wtAuth.path,
            agentName: "agent-a",
            task: "fix auth",
            branch: nil,
            worktree: wtAuth.path
        )

        let board = await service.getActiveWork(workspacePath: wtUi.path)
        XCTAssertEqual(board.registrations.count, 1)
        XCTAssertEqual(board.registrations.first?.agentName, "agent-a")
        XCTAssertEqual(board.registrations.first?.worktree, WorkspacePath.canonical(wtAuth.path))

        let dbAuth = RepositoryIdentity.databaseURL(from: wtAuth.path)
        let dbUi = RepositoryIdentity.databaseURL(from: wtUi.path)
        XCTAssertEqual(dbAuth.path, dbUi.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbAuth.path))
    }

    func testNonGitCheckoutFallsBackToCanonicalPath() {
        let ws = tempDir.appendingPathComponent("not-git").path
        try? FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        XCTAssertEqual(RepositoryIdentity.boardKey(from: ws), WorkspacePath.canonical(ws))
    }

    private func runGit(_ args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed: \(err)"
            ])
        }
    }
}
