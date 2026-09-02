import AnchorDomain
import Foundation

public protocol AgentTranscriptIndexing: Sendable {
    func indexTranscript(_ transcript: AgentTranscript) async throws
}

public protocol AgentSessionKnowledgeRecording: Sendable {
    func recordKnowledge(
        fromText text: String,
        forProject projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        at instant: Date
    ) async throws
}
