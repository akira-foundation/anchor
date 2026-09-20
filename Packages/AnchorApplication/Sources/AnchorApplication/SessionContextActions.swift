import AnchorDomain

public struct ListProjectSessionsRequest: Sendable {
    public let provider: AgentProvider?
    public let page: ContextPageRequest

    public init?(
        provider: AgentProvider? = nil, limit: Int? = nil, cursor: ContextPageCursor? = nil
    ) {
        guard let page = ContextPageRequest(limit: limit, cursor: cursor, maximumLimit: 100) else {
            return nil
        }
        self.provider = provider
        self.page = page
    }
}

public struct ReadProjectSessionRequest: Sendable {
    public let sessionID: SessionID
    public init(sessionID: SessionID) { self.sessionID = sessionID }
}

public struct ReadSessionMessagesRequest: Sendable {
    public let sessionID: SessionID
    public let page: ContextPageRequest

    public init?(sessionID: SessionID, limit: Int? = nil, cursor: ContextPageCursor? = nil) {
        guard
            let page = ContextPageRequest(
                limit: limit, cursor: cursor, defaultLimit: 50, maximumLimit: 200)
        else { return nil }
        self.sessionID = sessionID
        self.page = page
    }
}

public struct ListProjectSessionsAction: Action {
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

    public func perform(
        _ request: ListProjectSessionsRequest
    ) async throws -> ContextPage<SessionContextRecord> {
        try await queryContext(availability: availability) {
            let project = try await workspace.loadAuthorizedProjectContext()
            return try await sessions.listSessions(
                forProject: project.projectID, provider: request.provider, page: request.page)
        }
    }
}

public struct ReadProjectSessionAction: Action {
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

    public func perform(_ request: ReadProjectSessionRequest) async throws -> SessionContextRecord {
        try await queryContext(availability: availability) {
            let project = try await workspace.loadAuthorizedProjectContext()
            guard let record = try await sessions.loadSession(withIdentifier: request.sessionID),
                record.session.projectID == project.projectID
            else { throw ContextQueryFailure.entityNotFound }
            return record
        }
    }
}

public struct ReadSessionMessagesAction: Action {
    private let availability: any ContextAvailabilityReading
    private let workspace: any AuthorizedProjectContextReading
    private let entries: any ProjectConversationReading

    public init(
        workspace: any AuthorizedProjectContextReading, entries: any ProjectConversationReading,
        availability: any ContextAvailabilityReading
    ) {
        self.availability = availability
        self.workspace = workspace
        self.entries = entries
    }

    public func perform(
        _ request: ReadSessionMessagesRequest
    ) async throws -> ContextPage<ConversationEntry> {
        try await queryContext(availability: availability) {
            let project = try await workspace.loadAuthorizedProjectContext()
            return try await entries.loadConversationEntries(
                inSession: request.sessionID,
                forProject: project.projectID, page: request.page)
        }
    }
}
