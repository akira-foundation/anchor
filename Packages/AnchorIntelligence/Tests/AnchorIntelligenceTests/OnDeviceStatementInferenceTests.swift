import AnchorDomain
import Foundation
import Testing

@testable import AnchorIntelligence

private let liveInferenceIsAllowed =
    ProcessInfo.processInfo.environment["ANCHOR_INFERENCE_TESTS"] != nil

@Suite("Asking the machine's own model")
struct OnDeviceStatementInferenceTests {
    @Test("classification supports every durable knowledge kind")
    func classificationSupportsEveryKindAndAbsence() {
        #expect(
            Set(DurableKnowledgeKind.allCases.map(\.rawValue)) == [
                "decision", "risk", "summary", "todo", "question", "architecture",
            ])
    }

    @Test("the kind schema contains only its kind field")
    func kindSchemaContainsOnlyTheKindField() throws {
        let schema = DurableKindTag.generationSchema.debugDescription
        let fields = try #require(
            JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
        let order = try #require(fields["x-order"] as? [String])
        #expect(order == ["kind"])
    }

    @Test("unsupported input has an explicit absence classification")
    func unsupportedInputHasAbsenceClassification() {
        let instructions = TwoStageInferenceInstructions.eligibility

        #expect(instructions.contains("insufficientContext"))
        #expect(instructions.contains("conversation"))
    }

    @Test("category buckets map decision and risk to fixed distinct kinds")
    func categoryBucketsMapDecisionAndRiskToFixedDistinctKinds() throws {
        let supportingMessageID = MessageID()
        let references = [
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [supportingMessageID],
                evidenceText: "Keep inference opt-in")!,
            InferenceEvidenceReference(
                number: 2, supportingMessageIDs: [supportingMessageID],
                evidenceText: "The index can outgrow the disk")!,
        ]
        let decisionClaim = try eligibleClaim(reference: references[0])
        let riskClaim = try eligibleClaim(reference: references[1])
        let statements =
            ExtractiveDurableClaimClassification.statements(
                for: .decision,
                claim: decisionClaim, kinds: ["decision", "risk"])
            + ExtractiveDurableClaimClassification.statements(
                for: .risk,
                claim: riskClaim, kinds: ["decision", "risk"])

        #expect(statements.map(\.kind) == ["decision", "risk"])
        #expect(
            statements.map(\.supportingMessageIDs) == [
                [supportingMessageID], [supportingMessageID],
            ])
    }

    @Test("an inferred statement carries the messages and quotation that support it")
    func inferredStatementCarriesSupportingMessagesAndQuotation() throws {
        let proposalID = try #require(
            MessageID(rawValue: "11111111-1111-1111-1111-111111111111"))
        let confirmationID = try #require(
            MessageID(rawValue: "22222222-2222-2222-2222-222222222222"))

        let statement = InferredStatement(
            kind: "decision",
            summaryText: "Keep inference opt-in",
            supportingMessageIDs: [proposalID, confirmationID],
            evidenceText: "Keep inference opt-in")

        #expect(statement.supportingMessageIDs == [proposalID, confirmationID])
        #expect(statement.evidenceText == "Keep inference opt-in")
    }

    @Test("model output keeps valid message IDs and exact evidence")
    func modelOutputKeepsValidMessageIDsAndExactEvidence() throws {
        let supportingMessageID = try #require(
            MessageID(rawValue: "33333333-3333-3333-3333-333333333333"))
        let reference = InferenceEvidenceReference(
            number: 1, supportingMessageIDs: [supportingMessageID],
            evidenceText: "Keep inference opt-in")!
        let statements = ExtractiveDurableClaimClassification.statements(
            for: .decision,
            claim: try eligibleClaim(reference: reference), kinds: ["decision"])

        #expect(
            statements == [
                InferredStatement(
                    kind: "decision",
                    summaryText: "Keep inference opt-in",
                    supportingMessageIDs: [supportingMessageID],
                    evidenceText: "Keep inference opt-in")
            ])
    }

    @Test("a conversation with nothing in it is not asked about")
    func conversationWithNothingInItIsNotAskedAbout() async throws {
        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: "", keeping: 1_000), kinds: ["decision"]))

        #expect(statements.isEmpty)
    }

    @Test("an unavailable model is a refusal rather than an empty answer")
    func unavailableModelIsRefusalRatherThanEmptyAnswer() {
        #expect(throws: StatementInferenceUnavailable.self) {
            try requireAvailableInference(.unavailable("model is preparing"))
        }
    }

    private func eligibleClaim(
        reference: InferenceEvidenceReference
    ) throws
        -> EligibleInferenceClaim
    {
        let fragment = try #require(
            InferenceEvidenceFragmenter.fragments(in: reference.evidenceText).first)
        return try #require(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(
                    fragmentNumber: fragment.number, disposition: .durable),
                fragment: fragment, reference: reference))
    }
}

@Suite(
    "Asking the machine's own model, for real",
    .enabled(if: liveInferenceIsAllowed), .serialized
)
struct OnDeviceStatementInferenceLiveTests {
    private let kinds = ["decision", "todo", "risk", "question"]

    @Test("a machine that can answer says it is ready")
    func machineThatCanAnswerSaysItIsReady() async throws {
        #expect(await OnDeviceStatementInference().readiness() == .ready)
    }

    @Test("a decision stated in the conversation is reported as a decision")
    func decisionStatedInConversationIsReportedAsDecision() async throws {
        let proposalID = try #require(
            MessageID(rawValue: "44444444-4444-4444-4444-444444444444"))
        let confirmationID = try #require(
            MessageID(rawValue: "55555555-5555-5555-5555-555555555555"))
        let conversation = """
            <message id="\(proposalID.rawValue)" role="user">
            Keep inference opt-in
            </message>
            <message id="\(confirmationID.rawValue)" role="user">
            Yes
            </message>
            """

        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(
                    over: conversation, keeping: InferenceWindow.defaultCharacterBudget),
                kinds: kinds,
                evidenceReferences: [
                    InferenceEvidenceReference(
                        number: 1,
                        supportingMessageIDs: [proposalID, confirmationID],
                        evidenceText: "Keep inference opt-in", confirmationText: "Yes")!
                ]))

        let decision = try #require(statements.first { $0.kind == "decision" })

        #expect(Set(decision.supportingMessageIDs) == Set([proposalID, confirmationID]))
        #expect(decision.supportingMessageIDs.count == 2)
        #expect(decision.evidenceText == "Keep inference opt-in")
        #expect(statements.allSatisfy { kinds.contains($0.kind) })
    }

    @Test("a conversation about nothing in particular reports nothing in particular")
    func conversationAboutNothingInParticularReportsNothingInParticular() async throws {
        let greetingID = try #require(
            MessageID(rawValue: "66666666-6666-6666-6666-666666666666"))
        let thanksID = try #require(
            MessageID(rawValue: "77777777-7777-7777-7777-777777777777"))
        let conversation = """
            <message id="\(greetingID.rawValue)" role="user">
            Good morning. The weather is pleasant today.
            </message>
            <message id="\(thanksID.rawValue)" role="user">
            Thank you for the kind greeting.
            </message>
            """

        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(
                    over: conversation, keeping: InferenceWindow.defaultCharacterBudget),
                kinds: kinds,
                evidenceReferences: [
                    InferenceEvidenceReference(
                        number: 1, supportingMessageIDs: [greetingID],
                        evidenceText: "Good morning. The weather is pleasant today.")!,
                    InferenceEvidenceReference(
                        number: 2, supportingMessageIDs: [thanksID],
                        evidenceText: "Thank you for the kind greeting.")!,
                ]))

        #expect(statements.isEmpty)
    }

    @Test("the default window fits in the window the model actually has")
    func defaultWindowFitsInWindowModelActuallyHas() async throws {
        let sentences = [
            "user: where should the operation journal live?",
            "assistant: we decided to keep it on local disk only.",
            "user: what did the tests say?",
            "assistant: four hundred and eighty six passed, none failed.",
            "user: and the checkpoint?",
            "assistant: it now waits for the recording to succeed first.",
        ]
        let conversation = (0..<400).map { sentences[$0 % sentences.count] }
            .joined(separator: "\n")
        let window = InferenceWindow(
            over: conversation, keeping: InferenceWindow.defaultCharacterBudget)

        #expect(window.text.count == InferenceWindow.defaultCharacterBudget)

        _ = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: window, kinds: kinds,
                evidenceReferences: [
                    InferenceEvidenceReference(
                        number: 1, supportingMessageIDs: [MessageID()],
                        evidenceText: window.text)!
                ]))
    }
}
