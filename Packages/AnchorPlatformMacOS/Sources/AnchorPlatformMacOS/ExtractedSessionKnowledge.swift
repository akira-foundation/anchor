import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import Foundation

public struct ExtractedSessionKnowledge:
    AgentSessionKnowledgeRecording,
    AgentConversationKnowledgeRecording
{
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
        try await recordKnowledge(
            for: KnowledgeExtractionRequest(
                text: text,
                projectID: projectID,
                source: source,
                sourceContentHash: sourceContentHash,
                extractedAt: instant
            ))
    }

    public func recordKnowledge(
        fromMessages messages: [ConversationMessage],
        forProject projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        at instant: Date
    ) async throws {
        try await recordKnowledge(
            for: KnowledgeExtractionRequest(
                messages: messages,
                projectID: projectID,
                source: source,
                sourceContentHash: sourceContentHash,
                extractedAt: instant
            ))
    }

    private func recordKnowledge(for request: KnowledgeExtractionRequest) async throws {
        do {
            let entries = try await extractor.extractEntries(for: request)

            try await store.recordEntries(entries, supersedingEntriesFrom: request.source)
        } catch let refusal as KnowledgeExtractionRefusal {
            try await store.recordEntries(
                refusal.extractedEntries, supersedingEntriesFrom: request.source)

            throw refusal
        }
    }
}
