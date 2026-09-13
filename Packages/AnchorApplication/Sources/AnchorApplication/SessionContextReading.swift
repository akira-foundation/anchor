import AnchorDomain

public struct SessionContextRecord: Sendable, Hashable {
    public let session: AgentSession

    public init(session: AgentSession) {
        self.session = session
    }
}

public protocol SessionContextReading: Sendable {
    func listSessions(
        forProject projectID: ProjectID,
        provider: AgentProvider?,
        page: ContextPageRequest
    ) async throws -> ContextPage<SessionContextRecord>

    func loadSession(withIdentifier sessionID: SessionID) async throws -> SessionContextRecord?

    func loadConversationEntries(
        inSession sessionID: SessionID,
        page: ContextPageRequest
    ) async throws -> ContextPage<ConversationEntry>
}
