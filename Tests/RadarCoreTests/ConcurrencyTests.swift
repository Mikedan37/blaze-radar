import XCTest
@testable import RadarCore

final class ConcurrencyTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-concurrency-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testTenAgentsConcurrentRegisterUpdateSync() async throws {
        let ws = tempDir.path
        let agentCount = 10
        let findingsPerAgent = 5

        let registrations = try await withThrowingTaskGroup(of: AgentRegistration.self) { group in
            for i in 0..<agentCount {
                group.addTask {
                    let service = AwarenessService(store: BlazeDBAwarenessStore())
                    return try await service.register(
                        workspacePath: ws,
                        agentName: "agent-\(i)",
                        task: "task-\(i)",
                        branch: "fix/agent-\(i)",
                        worktree: ws
                    )
                }
            }
            var results: [AgentRegistration] = []
            for try await reg in group { results.append(reg) }
            return results
        }

        XCTAssertEqual(registrations.count, agentCount)
        XCTAssertEqual(Set(registrations.map(\.id)).count, agentCount)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (i, reg) in registrations.enumerated() {
                group.addTask {
                    let service = AwarenessService(store: BlazeDBAwarenessStore())
                    for j in 0..<findingsPerAgent {
                        _ = try await service.update(
                            workspacePath: ws,
                            registrationId: reg.id,
                            patch: UpdateAgentRequest(
                                workspacePath: ws,
                                registrationId: reg.id.uuidString,
                                discoveredFacts: ["finding-\(i)-\(j)"]
                            )
                        )
                    }
                }
            }
            try await group.waitForAll()
        }

        try await withThrowingTaskGroup(of: ActiveWorkSnapshot.self) { group in
            for reg in registrations {
                group.addTask {
                    let service = AwarenessService(store: BlazeDBAwarenessStore())
                    return await service.sync(workspacePath: ws, registrationId: reg.id)
                }
            }
            for try await snapshot in group {
                XCTAssertFalse(snapshot.registrations.isEmpty)
            }
        }

        let verify = AwarenessService(store: BlazeDBAwarenessStore())
        let snapshot = await verify.getActiveWork(workspacePath: ws)
        XCTAssertEqual(snapshot.registrations.count, agentCount)

        var allFindings: [String] = []
        for reg in snapshot.registrations {
            XCTAssertEqual(reg.discoveredFacts.count, findingsPerAgent, "Agent \(reg.agentName) lost findings")
            allFindings.append(contentsOf: reg.discoveredFacts)
        }

        XCTAssertEqual(allFindings.count, agentCount * findingsPerAgent)
        XCTAssertEqual(Set(allFindings).count, agentCount * findingsPerAgent, "Duplicate or lost finding detected")

        let store = BlazeDBAwarenessStore()
        let rawFindings = try await store.load(workspacePath: ws)
            .flatMap(\.discoveredFacts)
        XCTAssertEqual(rawFindings.count, agentCount * findingsPerAgent)
    }
}
