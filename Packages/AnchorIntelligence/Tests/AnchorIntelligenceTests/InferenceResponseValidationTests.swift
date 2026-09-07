import AnchorDomain
import Testing

@testable import AnchorIntelligence

struct InferenceResponseValidationTests {
    @Test func rejectsAmbiguousRequestNumbersBeforeModelInference() async throws {
        let first = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()],
                evidenceText: "Always review changes."))
        let second = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()],
                evidenceText: "Always require tests."))
        #expect(throws: InvalidInferenceResponse.duplicateReferenceNumbers) {
            try OnDeviceStatementInference.requireUniqueReferenceNumbers([first, second])
        }
        await #expect(throws: InvalidInferenceResponse.duplicateReferenceNumbers) {
            try await OnDeviceStatementInference().inferStatements(
                for: InferenceRequest(
                    window: InferenceWindow(over: "Authorized references", keeping: 100),
                    kinds: ["decision"], evidenceReferences: [first, second]))
        }
        try OnDeviceStatementInference.requireUniqueReferenceNumbers([first])
    }

    @Test func rejectsIncompleteOrContradictoryResponses() {
        let reference = InferenceEvidenceReference(
            number: 1, supportingMessageIDs: [MessageID()], evidenceText: "Always review changes.")!
        let fragment = InferenceEvidenceFragmenter.fragments(in: reference.evidenceText)[0]
        for invalidNumber in [-1, 0, 2, 99] {
            #expect(throws: InvalidClaimInferenceResponse.invalidReference) {
                try InferenceClaimEligibility.durableClaim(
                    from: FragmentEligibilityDraft(
                        fragmentNumber: invalidNumber, disposition: .durable),
                    fragment: fragment, reference: reference)
            }
        }
    }

    @Test func acceptsTransientClassificationAlongsideStandingDecision() throws {
        let reference = InferenceEvidenceReference(
            number: 1, supportingMessageIDs: [MessageID()],
            evidenceText: "Repair the failure. Always review independently.")!
        let fragments = InferenceEvidenceFragmenter.fragments(in: reference.evidenceText)
        #expect(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(fragmentNumber: 1, disposition: .immediateTask),
                fragment: fragments[0], reference: reference) == nil)
        #expect(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(fragmentNumber: 2, disposition: .durable),
                fragment: fragments[1], reference: reference) != nil)
    }

    @Test func acceptsExplicitNegativeClassification() throws {
        let reference = InferenceEvidenceReference(
            number: 1, supportingMessageIDs: [MessageID()], evidenceText: "Good morning.")!
        let fragment = InferenceEvidenceFragmenter.fragments(in: reference.evidenceText)[0]
        #expect(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(fragmentNumber: 1, disposition: .conversation),
                fragment: fragment, reference: reference) == nil)
    }
}
