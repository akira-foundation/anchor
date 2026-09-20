import AnchorApplication
import AnchorDomain

public typealias SearchHitKind = ProjectContextSearchHitKind
public typealias SearchHit = ProjectContextSearchHit

public protocol ContextSearching: Sendable {
    func indexTranscript(_ transcript: AgentTranscript) async throws
    func findContext(matching queryText: String, limit: Int) async throws -> [SearchHit]
}
