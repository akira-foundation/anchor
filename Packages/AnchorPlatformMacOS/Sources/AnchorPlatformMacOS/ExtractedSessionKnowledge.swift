import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import Foundation

public struct ExtractedSessionKnowledge: AgentSessionKnowledgeRecording {
    private let extractor: any KnowledgeExtracting
    private let store: any KnowledgeStore

    public init(extractor: any KnowledgeExtracting, store: any KnowledgeStore) {
        self.extractor = extractor
        self.store = store
    }

    public func recordKnowledge(
        fromText text: String,
        forProject projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        at instant: Date
    ) async throws {
        let entries = try await extractor.extractEntries(
            for: KnowledgeExtractionRequest(
                text: text,
                projectID: projectID,
                source: source,
                sourceContentHash: sourceContentHash,
                extractedAt: instant
            ))

        try await store.recordEntries(entries, supersedingEntriesFrom: source)
    }
}
