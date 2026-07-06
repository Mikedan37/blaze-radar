import XCTest
@testable import RadarCore

/// Proves v0.2 fixes against documented v0.1 failures.
final class V02RegressionTests: XCTestCase {
    private var tempDir: URL!
    private var tempHome: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-v02-\(UUID().uuidString)")
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-v02-home-\(UUID().uuidString)")
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

    // MARK: - Fix: per-agent identity (v0.1 overwrote single repo session file)

    func testV01StyleSharedSessionFileWouldOverwrite() throws {
        let ws = tempDir.path
        let legacyPath = tempDir.appendingPathComponent(".blaze/radar-session.json")
        try FileManager.default.createDirectory(at: legacyPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let agentA = #"{"registrationId":"aaa","workspacePath":"\#(ws)","agentName":"agent-a"}"#
        let agentB = #"{"registrationId":"bbb","workspacePath":"\#(ws)","agentName":"agent-b"}"#
        try agentA.write(to: legacyPath, atomically: true, encoding: .utf8)
        try agentB.write(to: legacyPath, atomically: true, encoding: .utf8)

        let onDisk = try String(contentsOf: legacyPath, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("bbb"))
        XCTAssertFalse(onDisk.contains("aaa"), "v0.1: second agent overwrote first agent's session")
    }

    func testV02PerAgentSessionsDoNotOverwrite() throws {
        let ws = tempDir.path
        let a = RadarAgentState.SessionFile(agentId: "id-a", name: "agent-a", workspace: ws)
        let b = RadarAgentState.SessionFile(agentId: "id-b", name: "agent-b", workspace: ws)
        try RadarAgentState.saveSession(a)
        try RadarAgentState.saveSession(b)

        XCTAssertEqual(RadarAgentState.findSession(workspacePath: ws, agentName: "agent-a")?.agentId, "id-a")
        XCTAssertEqual(RadarAgentState.findSession(workspacePath: ws, agentName: "agent-b")?.agentId, "id-b")
    }

    // MARK: - Fix: per-agent sync cursor

    func testV01StyleSharedSyncFileWouldOverwrite() throws {
        let ws = tempDir.path
        let legacyPath = tempDir.appendingPathComponent(".blaze/radar-sync.json")
        try FileManager.default.createDirectory(at: legacyPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let baselineA = #"{"syncedAt":"2026-01-01T00:00:00Z","registrations":{"a":{"discoveredFacts":["only-a"]}}}"#
        let baselineB = #"{"syncedAt":"2026-01-02T00:00:00Z","registrations":{"b":{"discoveredFacts":["only-b"]}}}"#
        try baselineA.write(to: legacyPath, atomically: true, encoding: .utf8)
        try baselineB.write(to: legacyPath, atomically: true, encoding: .utf8)

        let onDisk = try String(contentsOf: legacyPath, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("only-b"))
        XCTAssertFalse(onDisk.contains("only-a"), "v0.1: second sync clobbered first agent's cursor")
    }

    func testV02PerAgentSyncCursorsIndependent() throws {
        let ws = tempDir.path
        let reg = AgentRegistration(agentName: "x", task: "t", branch: "b", worktree: ws)
        var snapA = ActiveWorkSnapshot(registrations: [reg], relatedAreas: [], fileOverlaps: [])
        var snapB = snapA
        snapB.registrations[0].discoveredFacts = ["new-from-b"]

        try RadarAgentState.saveSync(workspacePath: ws, agentId: "agent-a", snapshot: snapA)
        try RadarAgentState.saveSync(workspacePath: ws, agentId: "agent-b", snapshot: snapB)

        let cursorA = RadarAgentState.loadSync(workspacePath: ws, agentId: "agent-a")
        let cursorB = RadarAgentState.loadSync(workspacePath: ws, agentId: "agent-b")
        XCTAssertEqual(cursorA?.registrations.values.first?.discoveredFacts, [])
        XCTAssertEqual(cursorB?.registrations.values.first?.discoveredFacts, ["new-from-b"])
    }

    // MARK: - Fix: register resume (v0.1 always minted new UUID)

    func testRegisterResumePreservesAgentId() throws {
        let ws = tempDir.path
        let original = RadarAgentState.SessionFile(agentId: UUID().uuidString, name: "claude-a", workspace: ws)
        try RadarAgentState.saveSession(original)

        let resumed = RadarAgentState.findSession(workspacePath: ws, agentName: "claude-a")
        XCTAssertEqual(resumed?.agentId, original.agentId)
    }

    // MARK: - Fix: idle/stale lifecycle (v0.1 auto-withdrew at 30m)

    func testLongSilenceMarksIdleNotWithdrawn() async throws {
        let service = AwarenessService(store: BlazeDBAwarenessStore())
        let ws = tempDir.path
        let reg = try await service.register(workspacePath: ws, agentName: "a", task: "t", branch: "b", worktree: ws)

        var stored = try await BlazeDBAwarenessStore().find(workspacePath: ws, id: reg.id)!
        stored.lastSeen = Date().addingTimeInterval(-35 * 60)
        try await BlazeDBAwarenessStore().upsert(workspacePath: ws, registration: stored)

        let snapshot = await service.getActiveWork(workspacePath: ws)
        let onBoard = snapshot.registrations.first { $0.id == reg.id }
        XCTAssertEqual(onBoard?.status, .idle)
        XCTAssertTrue(onBoard != nil, "v0.2: agent still on board when idle")
    }

    func testStaleAfterLongSilenceStillOnBoard() async throws {
        let service = AwarenessService(store: BlazeDBAwarenessStore())
        let ws = tempDir.path
        let reg = try await service.register(workspacePath: ws, agentName: "a", task: "t", branch: "b", worktree: ws)

        var stored = try await BlazeDBAwarenessStore().find(workspacePath: ws, id: reg.id)!
        stored.lastSeen = Date().addingTimeInterval(-65 * 60)
        try await BlazeDBAwarenessStore().upsert(workspacePath: ws, registration: stored)

        let snapshot = await service.getActiveWork(workspacePath: ws)
        let onBoard = snapshot.registrations.first { $0.id == reg.id }
        XCTAssertEqual(onBoard?.status, .stale)
        XCTAssertNotEqual(onBoard?.status, .withdrawn)
    }

    // MARK: - Fix: partial sync truth (v0.1 silent try?)

    func testSyncResultReportsPartialStatus() {
        let snapshot = ActiveWorkSnapshot(registrations: [], relatedAreas: [], fileOverlaps: [])
        let ok = SyncResult(snapshot: snapshot, heartbeatUpdated: true, gitRefreshed: true)
        let partial = SyncResult(snapshot: snapshot, heartbeatUpdated: false, gitRefreshed: false, warnings: ["git refresh failed"])

        XCTAssertTrue(ok.formatStatusLines().contains("✓ git refresh"))
        XCTAssertTrue(partial.formatStatusLines().contains("⚠ git refresh failed"))
        XCTAssertTrue(partial.formatStatusLines().contains("⚠ heartbeat not updated"))
    }

    // MARK: - Unchanged: core engine still works

    func testTwoAgentsShareFindingsViaBlazeDB() async throws {
        let service = AwarenessService(store: BlazeDBAwarenessStore())
        let ws = tempDir.path

        let a = try await service.register(workspacePath: ws, agentName: "agent-a", task: "fix scheduler", branch: "fix/a", worktree: ws)
        _ = try await service.register(workspacePath: ws, agentName: "agent-b", task: "fix signup", branch: "fix/b", worktree: ws)
        _ = try await service.update(
            workspacePath: ws,
            registrationId: a.id,
            patch: UpdateAgentRequest(
                workspacePath: ws,
                registrationId: a.id.uuidString,
                discoveredFacts: ["Found: missing attention arbiter"]
            )
        )

        let board = await service.getActiveWork(workspacePath: ws)
        let agentA = board.registrations.first { $0.agentName == "agent-a" }
        XCTAssertTrue(agentA?.discoveredFacts.first?.contains("attention arbiter") == true)
        XCTAssertEqual(board.registrations.count, 2)
    }
}
