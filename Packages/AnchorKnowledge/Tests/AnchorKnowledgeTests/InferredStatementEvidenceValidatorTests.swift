import AnchorDomain
import AnchorIntelligence
import Foundation
import Testing

@testable import AnchorKnowledge

@Suite("Rejecting inference without authorized evidence")
struct InferredStatementEvidenceValidatorTests {
    @Test("a supported candidate is normalized without changing its evidence")
    func supportedCandidateIsNormalizedWithoutChangingEvidence() throws {
        let proposalID = MessageID()
        let confirmationID = MessageID()
        let evidenceText = "Keep inference opt-in"
        let authorizedWindow = try window(units: [
            [
                (proposalID, "Proposal: \(evidenceText)"),
                (confirmationID, "Approved"),
            ]
        ])
        let candidate = InferredStatement(
            kind: "DECISION",
            summaryText: "  Keep inference opt-in\n",
            supportingMessageIDs: [proposalID, confirmationID],
            evidenceText: evidenceText)
        let expectedStatement = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [proposalID, confirmationID],
            evidenceText: evidenceText)

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(assessment.acceptedStatements == [expectedStatement])
        #expect(assessment.rejections.isEmpty)
    }

    @Test("an invalid kind is rejected before its other defects")
    func invalidKindIsRejectedBeforeOtherDefects() throws {
        let authorizedWindow = try window(units: [[(MessageID(), "Authorized")]])
        let candidate = InferredStatement(kind: "epiphany", summaryText: "")

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(assessment.rejections.map(\.reason) == [.invalidKind])
    }

    @Test("an empty summary is rejected before missing support")
    func emptySummaryIsRejectedBeforeMissingSupport() throws {
        let authorizedWindow = try window(units: [[(MessageID(), "Authorized")]])
        let candidate = InferredStatement(kind: "todo", summaryText: " \n ")

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(assessment.rejections.map(\.reason) == [.emptySummary])
    }

    @Test("a candidate must cite at least one message before evidence is checked")
    func candidateMustCiteAtLeastOneMessageBeforeEvidenceIsChecked() throws {
        let authorizedWindow = try window(units: [[(MessageID(), "Authorized")]])
        let candidate = InferredStatement(kind: "risk", summaryText: "Unbounded growth")

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(assessment.rejections.map(\.reason) == [.missingSupportingMessage])
    }

    @Test("an unknown message is rejected before evidence is checked")
    func unknownMessageIsRejectedBeforeEvidenceIsChecked() throws {
        let authorizedWindow = try window(units: [[(MessageID(), "Authorized")]])
        let candidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [MessageID()])

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(assessment.rejections.map(\.reason) == [.unknownSupportingMessage])
    }

    @Test("supporting messages from different authorized units are rejected")
    func supportingMessagesFromDifferentAuthorizedUnitsAreRejected() throws {
        let firstMessageID = MessageID()
        let secondMessageID = MessageID()
        let authorizedWindow = try window(units: [
            [(firstMessageID, "First authorized unit")],
            [(secondMessageID, "Second authorized unit")],
        ])
        let candidate = InferredStatement(
            kind: "summary",
            summaryText: "Two unrelated units",
            supportingMessageIDs: [firstMessageID, secondMessageID])

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(assessment.rejections.map(\.reason) == [.supportingMessagesCrossUnits])
    }

    @Test("blank evidence is rejected")
    func blankEvidenceIsRejected() throws {
        let messageID = MessageID()
        let authorizedWindow = try window(units: [[(messageID, "Literal evidence")]])
        let candidate = InferredStatement(
            kind: "architecture",
            summaryText: "Use a local index",
            supportingMessageIDs: [messageID],
            evidenceText: " \n ")

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(assessment.rejections.map(\.reason) == [.missingEvidence])
    }

    @Test("evidence must occur literally in a cited transmitted fragment")
    func evidenceMustOccurLiterallyInCitedTransmittedFragment() throws {
        let messageID = MessageID()
        let authorizedWindow = try window(units: [[(messageID, "Keep inference opt-in")]])
        let candidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [messageID],
            evidenceText: "Inference should remain optional")

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(assessment.rejections.map(\.reason) == [.evidenceIsNotLiteral])
    }

    @Test("evidence in only an uncited transmitted fragment is rejected")
    func evidenceInOnlyUncitedTransmittedFragmentIsRejected() throws {
        let citedMessageID = MessageID()
        let uncitedMessageID = MessageID()
        let authorizedWindow = try window(units: [
            [(citedMessageID, "Cited fragment")],
            [(uncitedMessageID, "Evidence belongs to this fragment")],
        ])
        let candidate = InferredStatement(
            kind: "decision",
            summaryText: "Evidence belongs elsewhere",
            supportingMessageIDs: [citedMessageID],
            evidenceText: "Evidence belongs to this fragment")

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(assessment.rejections.map(\.reason) == [.evidenceIsNotLiteral])
    }

    @Test("evidence omitted by truncation is not treated as transmitted")
    func evidenceOmittedByTruncationIsNotTreatedAsTransmitted() throws {
        let messageID = MessageID()
        let omittedEvidence = "Evidence outside the retained suffix"
        let authorizedWindow = try window(
            units: [[(messageID, omittedEvidence + String(repeating: "x", count: 200))]],
            characterBudget: 120)
        let transmittedFragment = try #require(authorizedWindow.fragmentsByMessageID[messageID])
        let candidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep the suffix",
            supportingMessageIDs: [messageID],
            evidenceText: omittedEvidence)

        #expect(!transmittedFragment.contains(omittedEvidence))

        let assessment = InferredStatementEvidenceValidator().assess(
            [candidate], in: authorizedWindow)

        #expect(
            assessment.rejections.map(\.reason) == [.supportingMessagesDoNotMatchAuthorizedUnit])
    }

    @Test("normalized duplicates keep only their first supported candidate")
    func normalizedDuplicatesKeepOnlyFirstSupportedCandidate() throws {
        let messageID = MessageID()
        let authorizedWindow = try window(units: [
            [
                (messageID, "Keep local. Retain exact evidence.")
            ]
        ])
        let firstCandidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep local",
            supportingMessageIDs: [messageID],
            evidenceText: "Keep local")
        let duplicateCandidate = InferredStatement(
            kind: "DECISION",
            summaryText: " Keep local\n",
            supportingMessageIDs: [messageID],
            evidenceText: "Retain exact evidence")

        let assessment = InferredStatementEvidenceValidator().assess(
            [firstCandidate, duplicateCandidate], in: authorizedWindow)

        #expect(assessment.acceptedStatements == [firstCandidate])
        #expect(assessment.rejections.map(\.reason) == [.duplicate])
    }

    @Test("supporting message order must match the authorized unit")
    func supportingMessageOrderMustMatchAuthorizedUnit() throws {
        let firstMessageID = MessageID()
        let secondMessageID = MessageID()
        let authorizedWindow = try window(units: [
            [
                (firstMessageID, "Keep inference opt-in"),
                (secondMessageID, "Approved"),
            ]
        ])
        let firstCandidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [firstMessageID, secondMessageID],
            evidenceText: "Keep inference opt-in")
        let reorderedCandidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [secondMessageID, firstMessageID],
            evidenceText: "Approved")

        let assessment = InferredStatementEvidenceValidator().assess(
            [firstCandidate, reorderedCandidate], in: authorizedWindow)

        #expect(assessment.acceptedStatements == [firstCandidate])
        #expect(
            assessment.rejections.map(\.reason)
                == [.supportingMessagesDoNotMatchAuthorizedUnit])
    }

    @Test("one unsupported candidate does not discard a supported candidate")
    func unsupportedCandidateDoesNotDiscardSupportedCandidate() throws {
        let messageID = MessageID()
        let authorizedWindow = try window(units: [[(messageID, "Keep inference opt-in")]])
        let supportedCandidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [messageID],
            evidenceText: "Keep inference opt-in")
        let unsupportedCandidate = InferredStatement(
            kind: "risk",
            summaryText: "Unknown risk",
            supportingMessageIDs: [MessageID()],
            evidenceText: "Unknown risk")

        let assessment = InferredStatementEvidenceValidator().assess(
            [supportedCandidate, unsupportedCandidate], in: authorizedWindow)

        #expect(assessment.acceptedStatements == [supportedCandidate])
        #expect(assessment.rejections.map(\.reason) == [.unknownSupportingMessage])
    }

    @Test("an invalid candidate does not reserve a later valid candidate identity")
    func invalidCandidateDoesNotReserveLaterValidCandidateIdentity() throws {
        let messageID = MessageID()
        let authorizedWindow = try window(units: [[(messageID, "Keep inference opt-in")]])
        let invalidCandidate = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [messageID],
            evidenceText: "Not literal")
        let validCandidate = InferredStatement(
            kind: "DECISION",
            summaryText: " Keep inference opt-in\n",
            supportingMessageIDs: [messageID],
            evidenceText: "Keep inference opt-in")
        let expectedStatement = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [messageID],
            evidenceText: "Keep inference opt-in")

        let assessment = InferredStatementEvidenceValidator().assess(
            [invalidCandidate, validCandidate], in: authorizedWindow)

        #expect(assessment.acceptedStatements == [expectedStatement])
        #expect(assessment.rejections.map(\.reason) == [.evidenceIsNotLiteral])
    }

    private func window(
        units: [[(MessageID, String)]],
        characterBudget: Int = InferenceWindow.defaultCharacterBudget
    ) throws -> AuthorizedInferenceWindow {
        let authorizedUnits = try units.map { fragments in
            try #require(
                AuthorizedConversationUnit(
                    fragmentsByMessageID: Dictionary(uniqueKeysWithValues: fragments),
                    messageIDs: fragments.map(\.0)))
        }

        return AuthorizedInferenceWindow(
            units: authorizedUnits,
            characterBudget: characterBudget)
    }
}
