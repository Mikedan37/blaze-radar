import Foundation
import BlazeDB

public enum RadarFindingType: String, Codable, Sendable {
    case discovered
    case negated
    case invariant
    case test
    case question
    case hypothesis
}

/// Agent registration core fields (BlazeDB `agents` collection).
public struct RadarAgent: BlazeStorable, Sendable {
    public var id: UUID
    public var workspacePath: String
    public var agentName: String
    public var task: String
    public var branch: String
    public var worktree: String
    public var status: String
    public var hypothesis: String?
    public var registeredAt: Date
    public var lastSeen: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        workspacePath: String,
        agentName: String,
        task: String,
        branch: String,
        worktree: String,
        status: String = AgentRegistrationStatus.active.rawValue,
        hypothesis: String? = nil,
        registeredAt: Date = Date(),
        lastSeen: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.workspacePath = workspacePath
        self.agentName = agentName
        self.task = task
        self.branch = branch
        self.worktree = worktree
        self.status = status
        self.hypothesis = hypothesis
        self.registeredAt = registeredAt
        self.lastSeen = lastSeen
        self.completedAt = completedAt
    }

    init(from registration: AgentRegistration, workspacePath: String) {
        self.id = registration.id
        self.workspacePath = workspacePath
        self.agentName = registration.agentName
        self.task = registration.task
        self.branch = registration.branch
        self.worktree = registration.worktree
        self.status = registration.status.rawValue
        self.hypothesis = registration.hypothesis
        self.registeredAt = registration.registeredAt
        self.lastSeen = registration.lastSeen
        self.completedAt = registration.completedAt
    }
}

/// Append-only finding/event (BlazeDB `findings` collection).
public struct RadarFinding: BlazeStorable, Sendable {
    public var id: UUID
    public var agentId: UUID
    public var workspacePath: String
    public var timestamp: Date
    public var type: String
    public var message: String

    public init(
        id: UUID = UUID(),
        agentId: UUID,
        workspacePath: String,
        timestamp: Date = Date(),
        type: RadarFindingType,
        message: String
    ) {
        self.id = id
        self.agentId = agentId
        self.workspacePath = workspacePath
        self.timestamp = timestamp
        self.type = type.rawValue
        self.message = message
    }
}

/// Git observation snapshot (BlazeDB `git_observations` collection).
public struct RadarGitObservation: BlazeStorable, Sendable {
    public var id: UUID
    public var agentId: UUID
    public var workspacePath: String
    public var branch: String
    public var headSHA: String
    public var changedFiles: [String]
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        agentId: UUID,
        workspacePath: String,
        branch: String,
        headSHA: String,
        changedFiles: [String],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.workspacePath = workspacePath
        self.branch = branch
        self.headSHA = headSHA
        self.changedFiles = changedFiles
        self.timestamp = timestamp
    }
}

/// Latest sync checkpoint per agent (BlazeDB `sync_state` collection).
/// One row per agent — updated in place on each sync, not append-only history.
/// Row `id` is independent from the agent registration id (same UUID would clobber the agent row).
public struct RadarSyncState: BlazeStorable, Sendable {
    public var id: UUID
    public var agentId: UUID
    public var workspacePath: String
    public var lastSyncAt: Date

    public init(id: UUID, agentId: UUID, workspacePath: String, lastSyncAt: Date = Date()) {
        self.id = id
        self.agentId = agentId
        self.workspacePath = workspacePath
        self.lastSyncAt = lastSyncAt
    }
}

enum RadarDBPaths {
    static let password = RepositoryIdentity.password

    static func databaseURL(workspacePath: String) -> URL {
        RepositoryIdentity.databaseURL(from: workspacePath)
    }
}
