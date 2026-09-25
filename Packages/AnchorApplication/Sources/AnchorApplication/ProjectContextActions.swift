import AnchorDomain
import Foundation

public protocol AuthorizedProjectContextReading: Sendable {
    func loadAuthorizedProjectContext() async throws -> ProjectContext
}

public struct ProjectContextRequest: Sendable {
    public init() {}
}

public struct ResolveCurrentProjectAction: Action {
    private let availability: any ContextAvailabilityReading
    private let workspace: any AuthorizedProjectContextReading

    public init(
        workspace: any AuthorizedProjectContextReading, availability: any ContextAvailabilityReading
    ) {
        self.availability = availability
        self.workspace = workspace
    }

    public func perform(_ request: ProjectContextRequest) async throws -> ProjectContext {
        try await queryContext(availability: availability) { _ in
            try await workspace.loadAuthorizedProjectContext()
        }
    }
}

public struct MinimalProjectResume: Sendable, Hashable {
    public let project: ProjectContext
    public let latestSession: AgentSession?
    public var lastActivityAt: Date? { latestSession?.updatedAt }
    public var lastAgentProvider: AgentProvider? { latestSession?.provider }

    public init(project: ProjectContext, latestSession: AgentSession?) {
        self.project = project
        self.latestSession = latestSession
    }
}

public struct BuildMinimalProjectResumeAction: Action {
    private let availability: any ContextAvailabilityReading
    private let workspace: any AuthorizedProjectContextReading
    private let sessions: any SessionContextReading

    public init(
        workspace: any AuthorizedProjectContextReading, sessions: any SessionContextReading,
        availability: any ContextAvailabilityReading
    ) {
        self.availability = availability
        self.workspace = workspace
        self.sessions = sessions
    }

    public func perform(_ request: ProjectContextRequest) async throws -> MinimalProjectResume {
        try await queryContext(availability: availability) { generation in
            let project = try await workspace.loadAuthorizedProjectContext()
            guard let page = ContextPageRequest(limit: 1, maximumLimit: 100) else {
                throw ContextQueryFailure.readFailed
            }
            let newest = try await sessions.listSessions(
                forProject: project.projectID, provider: nil, page: page,
                binding: ContextCursorBinding(
                    workspaceURL: project.workspaceURL, generation: generation))
            return MinimalProjectResume(
                project: project, latestSession: newest.records.first?.session)
        }
    }
}
