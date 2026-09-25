import AnchorDomain
import Foundation

public enum ProjectContextSearchHitKind: Sendable, Hashable {
    case message(ConversationRole)
    case toolActivity(String)
}

public struct ProjectContextSearchHit: Sendable, Hashable {
    public let sessionID: SessionID
    public let provider: AgentProvider
    public let kind: ProjectContextSearchHitKind
    public let excerpt: String
    public let timestamp: Date

    public init(
        sessionID: SessionID, provider: AgentProvider, kind: ProjectContextSearchHitKind,
        excerpt: String, timestamp: Date
    ) {
        self.sessionID = sessionID
        self.provider = provider
        self.kind = kind
        self.excerpt = excerpt
        self.timestamp = timestamp
    }
}

public protocol ProjectContextSearching: Sendable {
    func searchContext(
        forProject projectID: ProjectID, matching text: String, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<ProjectContextSearchHit>
}
