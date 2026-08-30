import AnchorDomain
import Foundation

public enum SearchHitKind: Sendable, Hashable {
    case message(ConversationRole)
    case toolActivity(String)
}

public struct SearchHit: Sendable, Hashable {
    public let sessionID: SessionID
    public let provider: AgentProvider
    public let kind: SearchHitKind
    public let excerpt: String
    public let timestamp: Date

    public init(
        sessionID: SessionID,
        provider: AgentProvider,
        kind: SearchHitKind,
        excerpt: String,
        timestamp: Date
    ) {
        self.sessionID = sessionID
        self.provider = provider
        self.kind = kind
        self.excerpt = excerpt
        self.timestamp = timestamp
    }
}

public protocol ContextSearching: Sendable {
    func indexTranscript(_ transcript: AgentTranscript) async throws
    func findContext(matching queryText: String, limit: Int) async throws -> [SearchHit]
}
