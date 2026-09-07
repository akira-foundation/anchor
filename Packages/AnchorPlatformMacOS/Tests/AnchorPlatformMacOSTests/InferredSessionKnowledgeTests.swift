import AnchorApplication
import AnchorDomain
import AnchorIntelligence
import AnchorKnowledge
import AnchorPersistence
import AnchorSearch
import Foundation
import Testing

@testable import AnchorPlatformMacOS

private struct ModelRefusal: Error {}

private struct RefusingStatementInference: StatementInferring {
    func readiness() async -> InferenceReadiness { .ready }

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        throw ModelRefusal()
    }
}

@Suite("Knowledge that survives a model refusal")
struct InferredSessionKnowledgeTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()
    private let instant = Date(timeIntervalSince1970: 1_000)

    @Test("a model refusal does not discard an explicit marker")
    func modelRefusalDoesNotDiscardExplicitMarker() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let action = RecordSessionContextAction(
            index: SearchedTranscriptIndex(
                search: try await SQLiteContextSearch(database: database)),
            knowledge: ExtractedSessionKnowledge(
                extractor: CompositeKnowledgeExtractor([
                    MarkedKnowledgeExtractor(),
                    InferredKnowledgeExtractor(inference: RefusingStatementInference()),
                ]),
                store: store
            )
        )
        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID,
                projectID: projectID,
                provider: .claude,
                startedAt: instant,
                updatedAt: instant
            ),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID(),
                        sessionID: sessionID,
                        role: .user,
                        content: "TODO: keep the explicit marker",
                        timestamp: instant
                    ))
            ]
        )
        let made = try #require(SessionArtifact.make(from: transcript, forProject: projectID))

        let report = try await action.recordSessionContext(
            RecordSessionContextRequest(
                artifact: made.artifact,
                content: made.content,
                contentHash: ContentHash.digest(of: made.content),
                recordedAt: instant
            ))
        let entries = try await store.entries(forProject: projectID, includingSuperseded: false)

        #expect(report.outcome == .indexed(messageCount: 1))
        #expect(report.knowledgeRefusal?.contains("ModelRefusal") == true)
        #expect(entries.map(\.kind) == [.todo])
        #expect(entries.map(\.origin) == [.marked])
    }
}
