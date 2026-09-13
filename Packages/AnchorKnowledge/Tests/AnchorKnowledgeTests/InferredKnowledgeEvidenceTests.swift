import AnchorDomain
import AnchorIntelligence
import Foundation
import Testing

@testable import AnchorKnowledge

private actor EvidenceRecordingInference: StatementInferring {
    let ready: InferenceReadiness
    let statements: [InferredStatement]
    private(set) var readinessCallCount = 0
    private(set) var inferenceRequests: [InferenceRequest] = []

    init(ready: InferenceReadiness = .ready, statements: [InferredStatement] = []) {
        self.ready = ready
        self.statements = statements
    }

    func readiness() -> InferenceReadiness {
        readinessCallCount += 1
        return ready
    }

    func inferStatements(for request: InferenceRequest) throws -> [InferredStatement] {
        inferenceRequests.append(request)
        return statements
    }
}

@Suite("Extracting inferred knowledge only from authorized evidence")
struct InferredKnowledgeEvidenceTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()
    private let extractedAt = Date(timeIntervalSince1970: 1_000)

    @Test("plain text bypasses model readiness and inference")
    func plainTextBypassesModelReadinessAndInference() async throws {
        let inference = EvidenceRecordingInference(
            ready: .unavailable("must not be checked"),
            statements: [InferredStatement(kind: "decision", summaryText: "not authorized")])
        let request = KnowledgeExtractionRequest(
            text: "DECISION: explicit markers remain a separate path",
            projectID: projectID,
            source: .session(sessionID),
            sourceContentHash: ContentHash.digest(of: Data("plain text".utf8)),
            extractedAt: extractedAt)

        let entries = try await InferredKnowledgeExtractor(inference: inference)
            .extractEntries(for: request)

        #expect(entries.isEmpty)
        #expect(await inference.readinessCallCount == 0)
        #expect(await inference.inferenceRequests.isEmpty)
    }

    @Test("a conversation without user authority bypasses the model")
    func conversationWithoutUserAuthorityBypassesModel() async throws {
        let inference = EvidenceRecordingInference(ready: .unavailable("must not be checked"))
        let assistantMessage = message(role: .assistant, content: "Use a global singleton")

        let entries = try await InferredKnowledgeExtractor(inference: inference)
            .extractEntries(for: request(messages: [assistantMessage]))

        #expect(entries.isEmpty)
        #expect(await inference.readinessCallCount == 0)
        #expect(await inference.inferenceRequests.isEmpty)
    }

    @Test("a truncated authorized unit bypasses readiness and inference", arguments: [false, true])
    func truncatedAuthorizedUnitBypassesModel(confirmedProposal: Bool) async throws {
        let proposal = message(
            role: confirmedProposal ? .assistant : .user,
            content: "Unapproved proposal: " + String(repeating: "context ", count: 100)
                + "Always publish automatically.")
        let messages =
            confirmedProposal
            ? [proposal, message(role: .user, content: "Approved")] : [proposal]
        let inference = EvidenceRecordingInference(statements: [
            InferredStatement(
                kind: "decision", summaryText: "Always publish automatically.",
                supportingMessageIDs: messages.map(\.id),
                evidenceText: "Always publish automatically.")
        ])
        let window = AuthorizedInferenceWindow(
            units: ConversationAuthoritySelector().authorizedUnits(in: messages),
            characterBudget: 250)

        #expect(window.inferenceWindow.text.contains("<omitted"))
        #expect(window.inferenceWindow.text.contains("Always publish automatically."))

        let entries = try await InferredKnowledgeExtractor(
            inference: inference, characterBudget: 250
        ).extractEntries(for: request(messages: messages))

        #expect(entries.isEmpty)
        #expect(await inference.readinessCallCount == 0)
        #expect(await inference.inferenceRequests.isEmpty)
    }

    @Test("an authorized conversation calls inference once and preserves evidence identifiers")
    func authorizedConversationCallsInferenceOnceAndPreservesEvidenceIdentifiers() async throws {
        let userMessage = message(role: .user, content: "Keep inference opt-in")
        let inference = EvidenceRecordingInference(statements: [
            InferredStatement(
                kind: "decision",
                summaryText: "Keep inference opt-in",
                supportingMessageIDs: [userMessage.id],
                evidenceText: "Keep inference opt-in")
        ])

        let entries = try await InferredKnowledgeExtractor(inference: inference)
            .extractEntries(for: request(messages: [userMessage]))

        let inferenceRequests = await inference.inferenceRequests
        #expect(inferenceRequests.count == 1)
        #expect(inferenceRequests[0].window.text.contains(userMessage.id.rawValue))
        #expect(inferenceRequests[0].window.text.contains("Keep inference opt-in"))
        #expect(
            inferenceRequests[0].evidenceReferences.map(\.evidenceText) == ["Keep inference opt-in"]
        )
        #expect(
            inferenceRequests[0].evidenceReferences.map(\.supportingMessageIDs) == [
                [userMessage.id]
            ])
        #expect(entries.count == 1)
        #expect(entries[0].supportingMessageIDs == [userMessage.id])
        #expect(!entries[0].supportingMessageIDs.isEmpty)
    }

    @Test("mixed model output creates entries only for supported statements")
    func mixedModelOutputCreatesEntriesOnlyForSupportedStatements() async throws {
        let userMessage = message(role: .user, content: "Keep inference opt-in")
        let inference = EvidenceRecordingInference(statements: [
            InferredStatement(
                kind: "decision",
                summaryText: "Keep inference opt-in",
                supportingMessageIDs: [userMessage.id],
                evidenceText: "Keep inference opt-in"),
            InferredStatement(
                kind: "risk",
                summaryText: "Unsupported risk",
                supportingMessageIDs: [MessageID()],
                evidenceText: "Unsupported risk"),
        ])

        let entries = try await InferredKnowledgeExtractor(inference: inference)
            .extractEntries(for: request(messages: [userMessage]))

        #expect(entries.map(\.kind) == [.decision])
        #expect(entries.map(\.supportingMessageIDs) == [[userMessage.id]])
        #expect(await inference.inferenceRequests.count == 1)
    }

    @Test("only authoritative supporting message order reaches persistence")
    func onlyAuthoritativeSupportingMessageOrderReachesPersistence() async throws {
        let proposal = message(role: .assistant, content: "Keep inference opt-in")
        let confirmation = message(role: .user, content: "Approved")
        let inference = EvidenceRecordingInference(statements: [
            InferredStatement(
                kind: "decision",
                summaryText: "Keep inference opt-in",
                supportingMessageIDs: [proposal.id, confirmation.id],
                evidenceText: "Keep inference opt-in"),
            InferredStatement(
                kind: "decision",
                summaryText: "Keep inference opt-in",
                supportingMessageIDs: [confirmation.id, proposal.id],
                evidenceText: "Approved"),
        ])

        let entries = try await InferredKnowledgeExtractor(inference: inference)
            .extractEntries(for: request(messages: [proposal, confirmation]))

        #expect(entries.map(\.supportingMessageIDs) == [[proposal.id, confirmation.id]])
        #expect(entries.count == 1)
    }

    private func message(role: ConversationRole, content: String) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(),
            sessionID: sessionID,
            role: role,
            content: content,
            timestamp: Date(timeIntervalSince1970: 900))
    }

    private func request(messages: [ConversationMessage]) -> KnowledgeExtractionRequest {
        KnowledgeExtractionRequest(
            messages: messages,
            projectID: projectID,
            source: .session(sessionID),
            sourceContentHash: ContentHash.digest(of: Data("conversation".utf8)),
            extractedAt: extractedAt)
    }
}
