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
        XCTAssertEqual(baseline.registrations.count, 1)

        _ = try await service.update(
            workspacePath: ws, registrationId: a.id,
            patch: UpdateAgentRequest(workspacePath: ws, registrationId: a.id.uuidString, discoveredFacts: ["finding-two"])
        )
        let after = await service.getActiveWork(workspacePath: ws)
        let reg = after.registrations.first!
        XCTAssertTrue(reg.discoveredFacts.contains("finding-two"))
    }

    func testRelatedAreaDetection() {
        let a = AgentRegistration(agentName: "A", task: "fix signup prompts", branch: "fix/a", worktree: "/tmp")
        let b = AgentRegistration(agentName: "B", task: "fix overlay interruptions", branch: "fix/b", worktree: "/tmp")
        let result = RelatedAreaDetector.analyze([a, b])
        XCTAssertFalse(result.related.isEmpty)
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
