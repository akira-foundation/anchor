import AnchorDomain

public struct SessionContextRecord: Sendable, Hashable {
    public let session: AgentSession
    public let messageCount: Int
    public let toolActivityCount: Int

    public init(session: AgentSession, messageCount: Int = 0, toolActivityCount: Int = 0) {
        self.session = session
        self.messageCount = messageCount
        self.toolActivityCount = toolActivityCount
    }
}

public protocol ProjectConversationReading: Sendable {
    func loadConversationEntries(
        inSession sessionID: SessionID, forProject projectID: ProjectID,
        page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<ConversationEntry>
}

public protocol SessionContextReading: Sendable {
    func listSessions(
        forProject projectID: ProjectID,
        provider: AgentProvider?,
        page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<SessionContextRecord>

    func loadSession(withIdentifier sessionID: SessionID) async throws -> SessionContextRecord?

    func loadConversationEntries(
        inSession sessionID: SessionID,
        page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<ConversationEntry>
}
