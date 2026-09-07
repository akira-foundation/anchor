import AnchorDomain
import AnchorIntelligence
import Testing

@testable import AnchorKnowledge

@Suite("Keeping complete authorized evidence units")
struct CompleteAuthorizedUnitEvidenceTests {
    @Test("a confirmed proposal cannot omit its confirming user message")
    func confirmedProposalCannotOmitConfirmingUserMessage() throws {
        let proposalID = MessageID()
        let confirmationID = MessageID()
        let authorizedWindow = try window(
            proposalID: proposalID,
            confirmationID: confirmationID)
        let incompleteCandidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [proposalID],
            evidenceText: "Keep inference opt-in")

        let assessment = InferredStatementEvidenceValidator().assess(
            [incompleteCandidate], in: authorizedWindow)

        #expect(assessment.acceptedStatements.isEmpty)
        #expect(
            assessment.rejections.map(\.reason)
                == [.supportingMessagesDoNotMatchAuthorizedUnit])
    }

    @Test("confirmed proposal support keeps authoritative conversation order")
    func confirmedProposalSupportKeepsAuthoritativeConversationOrder() throws {
        let proposalID = MessageID()
        let confirmationID = MessageID()
        let authorizedWindow = try window(
            proposalID: proposalID,
            confirmationID: confirmationID)
        let reorderedCandidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [confirmationID, proposalID],
            evidenceText: "Keep inference opt-in")

        let assessment = InferredStatementEvidenceValidator().assess(
            [reorderedCandidate], in: authorizedWindow)

        #expect(assessment.acceptedStatements.isEmpty)
        #expect(
            assessment.rejections.map(\.reason)
                == [.supportingMessagesDoNotMatchAuthorizedUnit])
    }

    private func window(
        proposalID: MessageID,
        confirmationID: MessageID
    ) throws -> AuthorizedInferenceWindow {
        let authorizedUnit = try #require(
            AuthorizedConversationUnit(
                fragmentsByMessageID: [
                    proposalID: "Keep inference opt-in",
                    confirmationID: "Approved",
                ],
                messageIDs: [proposalID, confirmationID]))

        return AuthorizedInferenceWindow(
            units: [authorizedUnit],
            characterBudget: InferenceWindow.defaultCharacterBudget)
    }
}
