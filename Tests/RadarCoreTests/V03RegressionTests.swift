import XCTest
@testable import RadarCore

/// v0.3: adoption + identity behavior — agents get used, not just stored correctly.
final class V03RegressionTests: XCTestCase {
    private var tempDir: URL!
    private var tempHome: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-v03-\(UUID().uuidString)")
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-v03-home-\(UUID().uuidString)")
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

    // MARK: - Workspace path aliasing (/tmp vs /private/tmp)

    func testRegisterWithTmpAliasVisibleViaPrivateTmpQuery() async throws {
        let service = AwarenessService(store: BlazeDBAwarenessStore())
        let viaTmp = "/tmp/radar-alias-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: viaTmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: viaTmp) }

        let viaPrivate = "/private\(viaTmp)"
        let tmpReal = (viaTmp as NSString).resolvingSymlinksInPath
        let privateReal = (viaPrivate as NSString).resolvingSymlinksInPath
        guard tmpReal == privateReal, viaTmp != viaPrivate else {
            throw XCTSkip("/tmp is not symlinked to /private/tmp on this host")
        }

        _ = try await service.register(
            workspacePath: viaTmp,
            agentName: "agent-a",
            task: "observe",
            branch: "main",
            worktree: viaTmp
        )

        let board = await service.getActiveWork(workspacePath: viaPrivate)
        XCTAssertEqual(board.registrations.count, 1)
        XCTAssertEqual(board.registrations.first?.agentName, "agent-a")
    }

    // MARK: - Default identity is generated, not hostname

    func testDefaultAgentNameIsGeneratedNotHostname() {
        let ws = tempDir.path
        let hostname = ProcessInfo.processInfo.hostName
        let first = RadarAgentState.resolveAgentName(workspacePath: ws, explicit: nil)
        let second = RadarAgentState.resolveAgentName(workspacePath: ws, explicit: nil)

        XCTAssertTrue(first.hasPrefix("agent-"))
        XCTAssertEqual(first, second, "same workspace reuses generated default")
        XCTAssertNotEqual(first, hostname)
    }

    func testSessionRespectsHOMEEnvironment() throws {
        let ws = tempDir.path
        let session = RadarAgentState.SessionFile(agentId: "home-test-id", name: "agent-home", workspace: ws)
        try RadarAgentState.saveSession(session)
        let expected = tempHome.appendingPathComponent(".blaze/radar")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }

    func testExplicitAgentNameOverridesDefault() {
        let ws = tempDir.path
        _ = RadarAgentState.resolveAgentName(workspacePath: ws, explicit: nil)
        XCTAssertEqual(RadarAgentState.resolveAgentName(workspacePath: ws, explicit: "claude-a"), "claude-a")
    }

    // MARK: - Resume refreshes volatile metadata

    func testResumeRefreshesTaskNotIdentity() async throws {
        let service = AwarenessService(store: BlazeDBAwarenessStore())
        let ws = tempDir.path

        let reg = try await service.register(
            workspacePath: ws,
            agentName: "agent-a",
            task: "working on scheduler",
            branch: "feat/scheduler",
            worktree: ws
        )

        let refreshed = try await service.refreshRegistration(
            workspacePath: ws,
            registrationId: reg.id,
            task: "fix signup",
            branch: "feat/signup",
            worktree: ws
        )

        XCTAssertEqual(refreshed.id, reg.id, "identity persists")
        XCTAssertEqual(refreshed.task, "fix signup")
        XCTAssertEqual(refreshed.branch, "feat/signup")

        let board = await service.getActiveWork(workspacePath: ws)
        let onBoard = board.registrations.first { $0.id == reg.id }
        XCTAssertEqual(onBoard?.task, "fix signup")
    }

    // MARK: - Scheduler incident: B sees A before acting

    func testSchedulerIncidentWarningBeforeAdjacentWork() async throws {
        let service = AwarenessService(store: BlazeDBAwarenessStore())
        let ws = tempDir.path

        let agentA = try await service.register(
            workspacePath: ws,
            agentName: "agent-a",
            task: "debug scheduler",
            branch: "feat/scheduler",
            worktree: ws
        )
        _ = try await service.update(
            workspacePath: ws,
            registrationId: agentA.id,
            patch: UpdateAgentRequest(
                workspacePath: ws,
                registrationId: agentA.id.uuidString,
                discoveredFacts: ["Scheduler uses cron in Sources/Scheduler"]
            )
        )

        let agentB = try await service.register(
            workspacePath: ws,
            agentName: "agent-b",
            task: "fix signup",
            branch: "feat/signup",
            worktree: ws
        )

        let syncResult = await service.sync(workspacePath: ws, registrationId: agentB.id)
        XCTAssertFalse(syncResult.snapshot.relatedAreas.isEmpty, "B should see related-area warning before editing")

        let agentAOnBoard = syncResult.snapshot.registrations.first { $0.agentName == "agent-a" }
        XCTAssertTrue(
            agentAOnBoard?.discoveredFacts.contains(where: { $0.contains("Scheduler") }) == true,
            "B sync should include A's scheduler finding"
        )
    }

    // MARK: - Sync with registration updates heartbeat

    func testSyncWithRegistrationUpdatesHeartbeat() async throws {
        let service = AwarenessService(store: BlazeDBAwarenessStore())
        let ws = tempDir.path
        let reg = try await service.register(
            workspacePath: ws, agentName: "agent-a", task: "t", branch: "b", worktree: ws
        )

        let result = await service.sync(workspacePath: ws, registrationId: reg.id)
        XCTAssertTrue(result.heartbeatUpdated)
        XCTAssertEqual(result.snapshot.registrations.count, 1)
    }
}
