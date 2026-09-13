import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import Foundation
import Testing

@testable import AnchorPlatformMacOS

private actor ContentCapturingKnowledgeExtractor: KnowledgeExtracting {
    private(set) var recordedContents: [KnowledgeExtractionContent] = []

    func extractEntries(for request: KnowledgeExtractionRequest) async throws -> [KnowledgeEntry] {
        recordedContents.append(request.content)

        return []
    }
}

private struct DiscardingKnowledgeStore: KnowledgeStore {
    func recordEntries(
        _ entries: [KnowledgeEntry], supersedingEntriesFrom source: KnowledgeEntrySource
    ) async throws {}

    func entries(
        forProject projectID: ProjectID, includingSuperseded: Bool
    ) async throws -> [KnowledgeEntry] {
        []
    }
}

@Suite("Turning structured session messages into extraction content")
struct ExtractedSessionKnowledgeTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()
    private let instant = Date(timeIntervalSince1970: 1_000)

    @Test("conversation recording retains messages as conversation extraction content")
    func conversationRecordingRetainsMessagesAsConversationExtractionContent() async throws {
        let expectedMessages = [
            ConversationMessage(
                id: MessageID(),
                sessionID: sessionID,
                role: .system,
                content: "Keep source identity.",
                timestamp: instant
            ),
            ConversationMessage(
                id: MessageID(),
                sessionID: sessionID,
                role: .user,
                content: "DECISION: preserve structured messages",
                timestamp: instant.addingTimeInterval(1)
            ),
        ]
        let extractor = ContentCapturingKnowledgeExtractor()
        let knowledge = ExtractedSessionKnowledge(
            extractor: extractor,
            store: DiscardingKnowledgeStore()
        )

        try await knowledge.recordKnowledge(
            fromMessages: expectedMessages,
            forProject: projectID,
            source: .session(sessionID),
            sourceContentHash: ContentHash.digest(of: Data("conversation".utf8)),
            at: instant
        )

        #expect(await extractor.recordedContents == [.conversation(expectedMessages)])
    }
}
