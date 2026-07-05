import Foundation

public enum AgentRegistrationStatus: String, Codable, Sendable {
    case active
    case idle
    case stale
    case done
    case withdrawn

    public var isOnBoard: Bool {
        switch self {
        case .active, .idle, .stale: return true
        case .done, .withdrawn: return false
        }
    }
}

public struct AgentRegistration: Codable, Sendable, Equatable {
    public var id: UUID
    public var agentName: String
    public var task: String
    public var branch: String
    public var worktree: String
    public var status: AgentRegistrationStatus
    public var headSHA: String?
    public var changedFiles: [String]
    public var hypothesis: String?
    public var discoveredFacts: [String]
    public var negatedHypotheses: [String]
    public var invariantsChanged: [String]
    public var testsAdded: [String]
    public var openQuestions: [String]
    public var registeredAt: Date
    public var lastSeen: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        agentName: String,
        task: String,
        branch: String,
        worktree: String,
        status: AgentRegistrationStatus = .active,
        headSHA: String? = nil,
        changedFiles: [String] = [],
        hypothesis: String? = nil,
        discoveredFacts: [String] = [],
        negatedHypotheses: [String] = [],
        invariantsChanged: [String] = [],
        testsAdded: [String] = [],
        openQuestions: [String] = [],
        registeredAt: Date = Date(),
        lastSeen: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.agentName = agentName
        self.task = task
        self.branch = branch
        self.worktree = worktree
        self.status = status
        self.headSHA = headSHA
        self.changedFiles = changedFiles
        self.hypothesis = hypothesis
        self.discoveredFacts = discoveredFacts
        self.negatedHypotheses = negatedHypotheses
        self.invariantsChanged = invariantsChanged
        self.testsAdded = testsAdded
        self.openQuestions = openQuestions
        self.registeredAt = registeredAt
        self.lastSeen = lastSeen
        self.completedAt = completedAt
    }
}

public struct RelatedAreaWarning: Codable, Sendable, Equatable {
    public var agentNames: [String]
    public var branches: [String]
    public var reason: String

    public init(agentNames: [String], branches: [String], reason: String) {
        self.agentNames = agentNames
        self.branches = branches
        self.reason = reason
    }
}

public struct FileOverlapWarning: Codable, Sendable, Equatable {
    public var path: String
    public var agentNames: [String]
    public var branches: [String]

    public init(path: String, agentNames: [String], branches: [String]) {
        self.path = path
        self.agentNames = agentNames
        self.branches = branches
    }
}

public struct ActiveWorkSnapshot: Codable, Sendable, Equatable {
    public var registrations: [AgentRegistration]
    public var relatedAreas: [RelatedAreaWarning]
    public var fileOverlaps: [FileOverlapWarning]

    public init(
        registrations: [AgentRegistration],
        relatedAreas: [RelatedAreaWarning],
        fileOverlaps: [FileOverlapWarning]
    ) {
        self.registrations = registrations
        self.relatedAreas = relatedAreas
        self.fileOverlaps = fileOverlaps
    }
}

public struct RegisterAgentResponse: Codable, Sendable {
    public let registrationId: String
    public let branch: String
    public let worktree: String

    public init(registrationId: String, branch: String, worktree: String) {
        self.registrationId = registrationId
        self.branch = branch
        self.worktree = worktree
    }
}

public struct UpdateAgentRequest: Codable, Sendable {
    public let workspacePath: String
    public let registrationId: String
    public let hypothesis: String?
    public let discoveredFacts: [String]
    public let negatedHypotheses: [String]
    public let invariantsChanged: [String]
    public let testsAdded: [String]
    public let openQuestions: [String]

    public init(
        workspacePath: String,
        registrationId: String,
        hypothesis: String? = nil,
        discoveredFacts: [String] = [],
        negatedHypotheses: [String] = [],
        invariantsChanged: [String] = [],
        testsAdded: [String] = [],
        openQuestions: [String] = []
    ) {
        self.workspacePath = workspacePath
        self.registrationId = registrationId
        self.hypothesis = hypothesis
        self.discoveredFacts = discoveredFacts
        self.negatedHypotheses = negatedHypotheses
        self.invariantsChanged = invariantsChanged
        self.testsAdded = testsAdded
        self.openQuestions = openQuestions
    }
}

public struct SyncResult: Codable, Sendable {
    public let snapshot: ActiveWorkSnapshot
    public let heartbeatUpdated: Bool
    public let gitRefreshed: Bool
    public let warnings: [String]

    public init(snapshot: ActiveWorkSnapshot, heartbeatUpdated: Bool, gitRefreshed: Bool, warnings: [String] = []) {
        self.snapshot = snapshot
        self.heartbeatUpdated = heartbeatUpdated
        self.gitRefreshed = gitRefreshed
        self.warnings = warnings
    }

    public func formatStatusLines() -> [String] {
        var lines: [String] = ["✓ synced findings"]
        lines.append(gitRefreshed ? "✓ git refresh" : "⚠ git refresh failed")
        lines.append(heartbeatUpdated ? "✓ heartbeat updated" : "⚠ heartbeat not updated")
        for warning in warnings { lines.append("⚠ \(warning)") }
        return lines
    }
}

public enum AwarenessError: Error, LocalizedError {
    case registrationNotFound
    case registrationNotActive

    public var errorDescription: String? {
        switch self {
        case .registrationNotFound: return "Radar registration not found"
        case .registrationNotActive: return "Radar registration is not active"
        }
    }
}
