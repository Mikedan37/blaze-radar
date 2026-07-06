import XCTest
@testable import RadarCore

final class RadarAgentStateTests: XCTestCase {
    private var tempHome: URL!

    override func setUp() {
        super.setUp()
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-agent-state-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("HOME", tempHome.path, 1)
    }

    override func tearDown() {
        unsetenv("HOME")
        try? FileManager.default.removeItem(at: tempHome)
        super.tearDown()
    }

    func testSeparateAgentSessionsSameWorkspace() throws {
        let ws = "/tmp/monorepo"
        let a = RadarAgentState.SessionFile(agentId: UUID().uuidString, name: "agent-a", workspace: ws)
        let b = RadarAgentState.SessionFile(agentId: UUID().uuidString, name: "agent-b", workspace: ws)
        try RadarAgentState.saveSession(a)
        try RadarAgentState.saveSession(b)

        XCTAssertEqual(RadarAgentState.findSession(workspacePath: ws, agentName: "agent-a")?.agentId, a.agentId)
        XCTAssertEqual(RadarAgentState.findSession(workspacePath: ws, agentName: "agent-b")?.agentId, b.agentId)
        XCTAssertNotEqual(a.agentId, b.agentId)
    }

    func testSeparateSyncCursors() throws {
        let ws = "/tmp/monorepo"
        let agentA = UUID().uuidString
        let agentB = UUID().uuidString
        let reg = AgentRegistration(agentName: "x", task: "t", branch: "b", worktree: ws)
        let snapA = ActiveWorkSnapshot(
            registrations: [reg],
            relatedAreas: [],
            fileOverlaps: []
        )
        var reg2 = reg
        reg2.discoveredFacts = ["finding-two"]
        let snapB = ActiveWorkSnapshot(
            registrations: [reg2],
            relatedAreas: [],
            fileOverlaps: []
        )

        try RadarAgentState.saveSync(workspacePath: ws, agentId: agentA, snapshot: snapA)
        try RadarAgentState.saveSync(workspacePath: ws, agentId: agentB, snapshot: snapB)

        let loadedA = RadarAgentState.loadSync(workspacePath: ws, agentId: agentA)
        let loadedB = RadarAgentState.loadSync(workspacePath: ws, agentId: agentB)
        XCTAssertEqual(loadedA?.registrations.values.first?.discoveredFacts, [])
        XCTAssertEqual(loadedB?.registrations.values.first?.discoveredFacts, ["finding-two"])
    }
}

final class PresenceStatusTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-presence-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testIdleNotWithdrawn() async throws {
        let service = AwarenessService(store: BlazeDBAwarenessStore())
        let ws = tempDir.path
        let reg = try await service.register(workspacePath: ws, agentName: "a", task: "t", branch: "b", worktree: ws)

        var stored = try await BlazeDBAwarenessStore().find(workspacePath: ws, id: reg.id)!
        stored.lastSeen = Date().addingTimeInterval(-35 * 60)
        try await BlazeDBAwarenessStore().upsert(workspacePath: ws, registration: stored)

        let snapshot = await service.getActiveWork(workspacePath: ws)
        let updated = snapshot.registrations.first { $0.id == reg.id }
        XCTAssertEqual(updated?.status, .idle)
    }
}
