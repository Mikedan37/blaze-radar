import XCTest
@testable import RadarCore

final class AwarenessTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeService() -> AwarenessService {
        AwarenessService(store: BlazeDBAwarenessStore())
    }

    func testCoreInvariant() async throws {
        let service = makeService()
        let ws = tempDir.path

        let a = try await service.register(
            workspacePath: ws, agentName: "agent-a", task: "fix prompt scheduler",
            branch: "fix/scheduler", worktree: ws
        )
        _ = try await service.register(
            workspacePath: ws, agentName: "agent-b", task: "fix signup interruptions",
            branch: "fix/signup", worktree: ws
        )
        _ = try await service.update(
            workspacePath: ws, registrationId: a.id,
            patch: UpdateAgentRequest(
                workspacePath: ws, registrationId: a.id.uuidString,
                discoveredFacts: ["Found: missing attention arbiter, don't build another scheduler"]
            )
        )

        let snapshot = await service.getActiveWork(workspacePath: ws)
        let other = snapshot.registrations.first { $0.agentName == "agent-a" }
        XCTAssertNotNil(other)
        XCTAssertTrue(other?.discoveredFacts.first?.contains("attention arbiter") == true)
    }

    func testSyncDeltaBaseline() async throws {
        let service = makeService()
        let ws = tempDir.path
        let a = try await service.register(workspacePath: ws, agentName: "a", task: "t", branch: "b", worktree: ws)
        _ = try await service.update(
            workspacePath: ws, registrationId: a.id,
            patch: UpdateAgentRequest(workspacePath: ws, registrationId: a.id.uuidString, discoveredFacts: ["finding-one"])
        )
        let baseline = await service.sync(workspacePath: ws, registrationId: nil)
        XCTAssertEqual(baseline.snapshot.registrations.count, 1)

        _ = try await service.update(
            workspacePath: ws, registrationId: a.id,
            patch: UpdateAgentRequest(workspacePath: ws, registrationId: a.id.uuidString, discoveredFacts: ["finding-two"])
        )
        let after = await service.getActiveWork(workspacePath: ws)
        let reg = after.registrations.first!
        XCTAssertTrue(reg.discoveredFacts.contains("finding-two"))
    }

    func testRelatedAreaDetection() {
        let a = AgentRegistration(agentName: "A", task: "fix auth middleware", branch: "fix/a", worktree: "/tmp/a")
        let b = AgentRegistration(agentName: "B", task: "auth signup bug", branch: "fix/b", worktree: "/tmp/b")
        let result = RelatedAreaDetector.analyze([a, b])
        XCTAssertFalse(result.related.isEmpty)
        XCTAssertTrue(result.related[0].reason.contains("auth"))
    }

    func testSameWorktreeSameFilesWarns() {
        let ws = "/Users/test/RadarTest"
        var a = AgentRegistration(agentName: "agent-4020", task: "working on auth", branch: "main", worktree: ws)
        var b = AgentRegistration(agentName: "agent-4021", task: "billing", branch: "main", worktree: ws)
        a.changedFiles = ["CLAUDE.md", ".blaze/", "README.md"]
        b.changedFiles = ["CLAUDE.md", ".blaze/", "README.md"]

        let result = RelatedAreaDetector.analyze([a, b])
        XCTAssertFalse(result.files.isEmpty, "same real files should warn")
        XCTAssertTrue(
            result.related.contains(where: { $0.reason.contains("Same files") }),
            "same changed files should surface as related-area warning"
        )
    }

    func testDifferentWorktreeRealOverlapStillWarns() {
        var a = AgentRegistration(agentName: "A", task: "auth", branch: "fix/a", worktree: "/tmp/wt-a")
        var b = AgentRegistration(agentName: "B", task: "billing", branch: "fix/b", worktree: "/tmp/wt-b")
        a.changedFiles = ["src/AuthService.swift"]
        b.changedFiles = ["src/AuthService.swift"]

        let result = RelatedAreaDetector.analyze([a, b])
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.files[0].path, "src/AuthService.swift")
    }

    func testInfrastructurePathsFiltered() {
        XCTAssertTrue(RadarCoordinationPaths.isInfrastructure("CLAUDE.md"))
        XCTAssertTrue(RadarCoordinationPaths.isInfrastructure(".blaze/radar/radar.blazedb"))
        XCTAssertFalse(RadarCoordinationPaths.isInfrastructure("src/main.swift"))
        XCTAssertEqual(
            RadarCoordinationPaths.coordinationRelevant(["CLAUDE.md", ".blaze/", "src/Foo.swift"]),
            ["src/Foo.swift"]
        )
    }

    func testObservingAgentsExcludedFromCollisions() {
        var active = AgentRegistration(agentName: "agent-a", task: "fixing auth middleware", branch: "main", worktree: "/tmp/a")
        active.discoveredFacts = ["token refresh bug"]
        var observing = AgentRegistration(agentName: "agent-b", task: "auth refactor", branch: "main", worktree: "/tmp/a", status: .observing)
        let result = RelatedAreaDetector.analyze([active, observing])
        XCTAssertTrue(result.related.isEmpty)
    }

    func testBlazeDBPersistsAcrossReopen() async throws {
        let ws = tempDir.path
        let serviceA = AwarenessService(store: BlazeDBAwarenessStore())
        let reg = try await serviceA.register(workspacePath: ws, agentName: "persist", task: "t", branch: "b", worktree: ws)
        _ = try await serviceA.update(
            workspacePath: ws, registrationId: reg.id,
            patch: UpdateAgentRequest(workspacePath: ws, registrationId: reg.id.uuidString, discoveredFacts: ["durable-finding"])
        )

        let serviceB = AwarenessService(store: BlazeDBAwarenessStore())
        let loaded = try await serviceB.getActiveWork(workspacePath: ws)
        XCTAssertEqual(loaded.registrations.count, 1)
        XCTAssertTrue(loaded.registrations[0].discoveredFacts.contains("durable-finding"))
    }
}
