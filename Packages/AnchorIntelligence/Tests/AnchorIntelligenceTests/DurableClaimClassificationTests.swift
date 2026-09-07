import AnchorDomain
import Testing

@testable import AnchorIntelligence

struct DurableClaimClassificationTests {
    @Test func kindSchemaExcludesGeneratedSummaries() throws {
        let schema = DurableKindTag.generationSchema.debugDescription
        #expect(schema.contains("decision"))
        #expect(!schema.contains("summaryText"))
    }

    @Test func resolvesDecisionAndRiskToOriginalEvidence() throws {
        let claim = try claim()
        let statements = ExtractiveDurableClaimClassification.statements(
            for: .decision,
            claim: claim, kinds: ["decision", "risk"])
        #expect(statements.map(\.kind) == ["decision"])
        #expect(
            statements.map(\.supportingMessageIDs) == [
                claim.reference.supportingMessageIDs
            ])
        #expect(
            statements.map(\.evidenceText) == [
                claim.reference.evidenceText
            ])
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
}
