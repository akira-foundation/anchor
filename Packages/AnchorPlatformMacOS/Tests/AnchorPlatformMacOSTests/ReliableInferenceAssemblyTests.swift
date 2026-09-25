import AnchorApplication
import AnchorDomain
import AnchorIntelligence
import AnchorKnowledge
import AnchorPersistence
import AnchorSearch
import AnchorStorage
import CryptoKit
import Foundation
import Testing

@testable import AnchorPlatformMacOS

private actor EvidencedStatementInference: StatementInferring {
    private let statement: InferredStatement
    private(set) var requests: [InferenceRequest] = []

    init(statement: InferredStatement) {
        self.statement = statement
    }

    func readiness() async -> InferenceReadiness { .ready }

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        requests.append(request)

        return [statement]
    }
}

@Suite("Reliable inference in the assembled macOS session context")
struct ReliableInferenceAssemblyTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()
    private let instant = Date(timeIntervalSince1970: 1_000)

    @Test("the assembled context persists only canonical conversation evidence")
    func assembledContextPersistsOnlyCanonicalConversationEvidence() async throws {
        let proposal = message(
            role: .assistant,
            content: "Keep knowledge inference opt-in.",
            secondsAfterStart: 0
        )
        let confirmation = message(role: .user, content: "ok", secondsAfterStart: 1)
        let toolActivity = ToolActivity(
            id: ToolActivityID(),
            sessionID: sessionID,
            toolName: "Bash",
            invocation: "xcodebuild test",
            outcome: "BUILD SUCCEEDED",
            failed: false,
            timestamp: instant.addingTimeInterval(2)
        )
        let inference = EvidencedStatementInference(
            statement: statement(proposal: proposal, confirmation: confirmation))
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: await assembleStorage(),
            inferringKnowledge: true,
            statementInference: inference,
            database: database
        )
        let transcript = AgentTranscript(
            session: session(),
            entries: [
                .message(proposal),
                .message(confirmation),
                .toolActivity(toolActivity),
            ]
        )
        let made = try #require(SessionArtifact.make(from: transcript, forProject: projectID))

        _ = await context.rebuilder.rebuild(
            from: [(artifact: made.artifact, content: made.content)],
            at: instant
        )

        let request = try #require(await inference.requests.only)
        let proposalRange = try #require(request.window.text.range(of: proposal.id.rawValue))
        let confirmationRange = try #require(
            request.window.text.range(of: confirmation.id.rawValue))

        #expect(proposalRange.lowerBound < confirmationRange.lowerBound)
        #expect(request.window.text.contains(toolActivity.id.rawValue) == false)
        #expect(request.window.text.contains(toolActivity.invocation) == false)

        let storedEntry = try #require(
            await store.entries(forProject: projectID, includingSuperseded: false).only)
        #expect(storedEntry.supportingMessageIDs == [proposal.id, confirmation.id])
        #expect(storedEntry.origin == .inferred)
        #expect(
            storedEntry.supportingMessageIDs.contains(where: {
                $0.rawValue == toolActivity.id.rawValue
            }) == false
        )
    }

    @Test("disabled inference does not call the supplied driver")
    func disabledInferenceDoesNotCallSuppliedDriver() async throws {
        let proposal = message(
            role: .assistant,
            content: "Keep knowledge inference opt-in.",
            secondsAfterStart: 0
        )
        let confirmation = message(role: .user, content: "ok", secondsAfterStart: 1)
        let inference = EvidencedStatementInference(
            statement: statement(proposal: proposal, confirmation: confirmation))
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: await assembleStorage(),
            statementInference: inference,
            database: SQLiteDatabase(fileURL: nil)
        )
        let transcript = AgentTranscript(
            session: session(),
            entries: [.message(proposal), .message(confirmation)]
        )
        let made = try #require(SessionArtifact.make(from: transcript, forProject: projectID))

        _ = await context.rebuilder.rebuild(
            from: [(artifact: made.artifact, content: made.content)],
            at: instant
        )

        #expect(await inference.requests.isEmpty)
    }

    private func assembleStorage() async -> AssembledContextStorage {
        await ContextStorageAssembly.assemble(
            reachingRemote: { nil },
            localRootURL: FileManager.default.temporaryDirectory
                .appending(path: "anchor-\(UUID().uuidString)"),
            key: SymmetricKey(size: .bits256)
        )
    }

    private func message(
        role: ConversationRole,
        content: String,
        secondsAfterStart: TimeInterval
    ) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(),
            sessionID: sessionID,
            role: role,
            content: content,
            timestamp: instant.addingTimeInterval(secondsAfterStart)
        )
    }

    private func statement(
        proposal: ConversationMessage,
        confirmation: ConversationMessage
    ) -> InferredStatement {
        InferredStatement(
            kind: "decision",
            summaryText: "Keep knowledge inference opt-in.",
            supportingMessageIDs: [proposal.id, confirmation.id],
            evidenceText: "Keep knowledge inference opt-in."
        )
    }

    private func session() -> AgentSession {
        AgentSession(
            id: sessionID,
            projectID: projectID,
            provider: .claude,
            startedAt: instant,
            updatedAt: instant
        )
    }

}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
