import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

private actor StructuredMessageTestIndex: AgentTranscriptIndexing {
    func indexTranscript(_ transcript: AgentTranscript) async throws {}
}

private actor ConversationKnowledgeRecorder: AgentConversationKnowledgeRecording {
    private(set) var recordedMessages: [ConversationMessage] = []

    func recordKnowledge(
        fromMessages messages: [ConversationMessage],
        forProject projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        at instant: Date
    ) async throws {
        recordedMessages = messages
    }
}

@Suite("Preserving a session conversation for knowledge extraction")
struct StructuredSessionKnowledgeRecordingTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()
    private let recordedAt = Date(timeIntervalSince1970: 1_000)

    private func makeOutOfOrderTranscript() -> (
        transcript: AgentTranscript, expectedMessages: [ConversationMessage]
    ) {
        let session = AgentSession(
            id: sessionID,
            projectID: projectID,
            provider: .claude,
            startedAt: recordedAt,
            updatedAt: recordedAt
        )
        let systemMessage = ConversationMessage(
            id: MessageID(),
            sessionID: sessionID,
            role: .system,
            content: "System context",
            timestamp: recordedAt
        )
        let userMessage = ConversationMessage(
            id: MessageID(),
            sessionID: sessionID,
            role: .user,
            content: "DECISION: preserve the source messages",
            timestamp: recordedAt.addingTimeInterval(1)
        )
        let assistantMessage = ConversationMessage(
            id: MessageID(),
            sessionID: sessionID,
            role: .assistant,
            content: "I will retain their original identity.",
            timestamp: recordedAt.addingTimeInterval(2)
        )

        return (
            AgentTranscript(
                session: session,
                entries: [
                    .message(assistantMessage),
                    .message(systemMessage),
                    .message(userMessage),
                ]
            ),
            [systemMessage, userMessage, assistantMessage]
        )
    }

    private func makeRequest(for transcript: AgentTranscript) throws -> RecordSessionContextRequest
    {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedTranscript = try encoder.encode(transcript)
        let artifact = try #require(
            Artifact(
                id: ArtifactID(),
                projectID: projectID,
                provider: .claude,
                name: AgentSessionArtifactNaming.name(forSession: sessionID, provider: .claude)
            )
        )

        return RecordSessionContextRequest(
            artifact: artifact,
            content: encodedTranscript,
            contentHash: ContentHash.digest(of: encodedTranscript),
            recordedAt: recordedAt
        )
    }

    @Test("conversation knowledge receives the original messages in conversation order")
    func conversationKnowledgeReceivesOriginalMessagesInConversationOrder() async throws {
        let transcriptAndMessages = makeOutOfOrderTranscript()
        let recorder = ConversationKnowledgeRecorder()

        _ = try await RecordSessionContextAction(
            index: StructuredMessageTestIndex(),
            conversationKnowledge: recorder
        ).perform(try makeRequest(for: transcriptAndMessages.transcript))

        #expect(await recorder.recordedMessages == transcriptAndMessages.expectedMessages)
    }
}
