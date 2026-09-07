import AnchorDomain
import Foundation
import Testing

@testable import AnchorIntelligence

struct ExtractiveDurableClassificationTests {
    @Test func currentWorkCannotPersistItsFailureAsRisk() {
        #expect(
            !ExtractiveDurableClaimClassification.kindIsPersistent(
                .risk, within: .currentWork, referenceIncludesImmediateTask: true))
        #expect(
            !ExtractiveDurableClaimClassification.kindIsPersistent(
                .architecture, within: .currentWork, referenceIncludesImmediateTask: true))
        #expect(
            ExtractiveDurableClaimClassification.kindIsPersistent(
                .risk, within: .currentWork, referenceIncludesImmediateTask: false))
        #expect(
            ExtractiveDurableClaimClassification.kindIsPersistent(
                .decision, within: .currentWork, referenceIncludesImmediateTask: true))
        #expect(
            !ExtractiveDurableClaimClassification.kindIsPersistent(
                .summary, within: .approvedProposal, referenceIncludesImmediateTask: false))
        #expect(
            ExtractiveDurableClaimClassification.kindIsPersistent(
                .risk, within: .mixed, referenceIncludesImmediateTask: true))
    }

    @Test func everyIntentKindAndImmediateTaskCombinationMatchesPersistencePolicy() {
        let intents: [ReferenceIntent] = [
            .currentWork, .tentativeProposal, .approvedProposal, .standingPolicy,
            .executionReport, .ordinaryConversation, .durableKnowledge, .mixed,
        ]
        for intent in intents {
            for kind in DurableKnowledgeKind.allCases {
                for includesImmediateTask in [false, true] {
                    #expect(
                        ExtractiveDurableClaimClassification.kindIsPersistent(
                            kind, within: intent,
                            referenceIncludesImmediateTask: includesImmediateTask)
                            == expectedPersistence(
                                kind: kind, intent: intent,
                                includesImmediateTask: includesImmediateTask))
                }
            }
        }
    }

    @Test func classificationInstructionsMatchSingleKindSchema() {
        #expect(TwoStageInferenceInstructions.classification.contains("one primary kind"))
        #expect(TwoStageInferenceInstructions.classification.contains("choose risk"))
        #expect(!TwoStageInferenceInstructions.classification.contains("comma-separated"))
        #expect(!TwoStageInferenceInstructions.classification.contains("separate summaries"))
    }

    @Test func generatedKindSchemaContainsEverySupportedExactKind() {
        let schema = DurableKindTag.generationSchema.debugDescription
        for kind in DurableKnowledgeKind.allCases {
            #expect(schema.contains("\"\(kind.rawValue)\""))
        }
    }

    @Test func generatedKindSchemaHasOneOutputField() throws {
        let schema = DurableKindTag.generationSchema.debugDescription
        let fields = try #require(
            JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
        #expect(fields["x-order"] as? [String] == ["kind"])
    }

    @Test func generatedKindSchemaDoesNotPermitFreeFormSummary() {
        let schema = DurableKindTag.generationSchema.debugDescription
        #expect(!schema.contains("summaryText"))
        #expect(!schema.contains("classifications"))
    }

    @Test func riskVerificationRequiresAnExactHarmQuote() {
        let schema = ExplicitHarmTag.generationSchema.debugDescription
        #expect(schema.contains("absent"))
        #expect(schema.contains("present"))
        #expect(schema.contains("harmfulOutcomeText"))
        #expect(schema.contains("possibilityOrFailureText"))
        #expect(TwoStageInferenceInstructions.explicitHarmVerification.contains("Never infer"))
        #expect(
            TwoStageInferenceInstructions.explicitHarmVerification.contains(
                "both copied texts empty"))
        #expect(
            TwoStageInferenceInstructions.explicitHarmVerification.contains(
                "consequence clause"))
        #expect(
            TwoStageInferenceInstructions.explicitHarmVerification.contains(
                "themselves name harm"))
        #expect(
            TwoStageInferenceInstructions.explicitHarmVerification.contains(
                "Depois de cada"))
        #expect(
            OnDeviceStatementInference.isVerifiedExplicitHarm(
                ExplicitHarmTag(
                    presence: .present, harmfulOutcomeText: "exhaust device storage",
                    possibilityOrFailureText: "could"),
                in: "Cached attachments could exhaust the device storage."))
        #expect(
            OnDeviceStatementInference.isVerifiedExplicitHarm(
                ExplicitHarmTag(
                    presence: .present, harmfulOutcomeText: "corrupt the index",
                    possibilityOrFailureText: "likely"),
                in: "This is likely to corrupt the index."))
        #expect(
            OnDeviceStatementInference.isVerifiedExplicitHarm(
                ExplicitHarmTag(
                    presence: .present, harmfulOutcomeText: "corromper o índice",
                    possibilityOrFailureText: "poderá"),
                in: "Isto poderá corromper o índice."))
        #expect(
            !OnDeviceStatementInference.isVerifiedExplicitHarm(
                ExplicitHarmTag(
                    presence: .present, harmfulOutcomeText: "data loss",
                    possibilityOrFailureText: "could"),
                in: "Ask before changing the database."))
        #expect(
            !OnDeviceStatementInference.isVerifiedExplicitHarm(
                ExplicitHarmTag(
                    presence: .present, harmfulOutcomeText: "  ",
                    possibilityOrFailureText: "could"),
                in: "Ask before changing the database."))
        #expect(
            !OnDeviceStatementInference.isVerifiedExplicitHarm(
                ExplicitHarmTag(
                    presence: .absent, harmfulOutcomeText: "cópia de segurança",
                    possibilityOrFailureText: "queres"),
                in: "Perguntar se queres criar uma cópia de segurança."))
    }

    @Test func rejectsWrongEmptyOrDuplicateKinds() throws {
        let claim = try claim()
        #expect(
            ExtractiveDurableClaimClassification.statements(
                for: .decision, claim: claim, kinds: ["risk"]
            ).isEmpty)
    }

    @Test func resolvesKindsWithExtractiveSummaryAndOriginalEvidence() throws {
        let claim = try claim()
        let statements = ExtractiveDurableClaimClassification.statements(
            for: .risk,
            claim: claim, kinds: ["decision", "risk"])

        #expect(statements.map(\.kind) == ["risk"])
        #expect(statements.map(\.summaryText) == [claim.evidenceText])
        #expect(
            statements.map(\.supportingMessageIDs) == [
                claim.reference.supportingMessageIDs
            ])
        #expect(
            statements.map(\.evidenceText) == [
                claim.reference.evidenceText
            ])
    }

    @Test func classifierPromptExcludesDiscardedReferenceContext() throws {
        let prompt = try ExtractiveDurableClaimClassification.prompt(for: claim())
        let fields = try #require(
            JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])

        #expect(Set(fields.keys) == ["claimNumber", "confirmation", "selectedClaim"])
        #expect(fields["selectedClaim"] as? String == "Keep the journal local.")
        #expect(!(prompt.contains("exhaust disk space")))
    }

    @Test func unrequestedKindsAreNotReturned() throws {
        let claim = try claim()
        #expect(
            ExtractiveDurableClaimClassification.statements(
                for: .risk,
                claim: claim, kinds: ["decision"]
            ).isEmpty)
    }

    private func claim() throws -> EligibleInferenceClaim {
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID(), MessageID()],
                evidenceText:
                    "Keep the journal local. An unbounded journal can exhaust disk space.",
                confirmationText: "Approved"))
        let fragment = try #require(
            InferenceEvidenceFragmenter.fragments(in: reference.evidenceText).first)
        return try #require(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(
                    fragmentNumber: fragment.number, disposition: .durable),
                fragment: fragment, reference: reference))
    }

    private func expectedPersistence(
        kind: DurableKnowledgeKind, intent: ReferenceIntent, includesImmediateTask: Bool
    ) -> Bool {
        switch intent {
        case .tentativeProposal, .executionReport, .ordinaryConversation:
            false
        case .currentWork:
            !includesImmediateTask || kind == .decision
        case .approvedProposal:
            [.decision, .risk, .todo, .question].contains(kind)
        case .standingPolicy:
            kind == .decision
        case .durableKnowledge, .mixed:
            true
        }
    }
}
