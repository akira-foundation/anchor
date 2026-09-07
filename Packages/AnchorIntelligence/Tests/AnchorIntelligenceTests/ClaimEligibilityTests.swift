import AnchorDomain
import Testing

@testable import AnchorIntelligence

struct ClaimEligibilityTests {
    @Test func rejectsUntrustedSegments() throws {
        let reference = try reference()
        let fragment = try #require(
            InferenceEvidenceFragmenter.fragments(in: reference.evidenceText).first)
        for untrustedNumber in [-1, 0, 2, 99] {
            #expect(throws: InvalidClaimInferenceResponse.invalidReference) {
                try InferenceClaimEligibility.durableClaim(
                    from: FragmentEligibilityDraft(
                        fragmentNumber: untrustedNumber, disposition: .durable),
                    fragment: fragment, reference: reference)
            }
        }
    }

    @Test func mixedMessageRetainsOnlyItsStandingRule() throws {
        let reference = try reference()
        let fragments = InferenceEvidenceFragmenter.fragments(in: reference.evidenceText)
        let rejected = try InferenceClaimEligibility.durableClaim(
            from: FragmentEligibilityDraft(fragmentNumber: 1, disposition: .immediateTask),
            fragment: fragments[0], reference: reference)
        let claim = try #require(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(fragmentNumber: 2, disposition: .durable),
                fragment: fragments[1], reference: reference))
        #expect(rejected == nil)
        #expect(claim.number == 2)
        #expect(claim.evidenceText == "Always review changes.")
        #expect(claim.reference == reference)
    }

    @Test func explicitNegativeRemainsEmpty() throws {
        let reference = try reference()
        #expect(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(fragmentNumber: 1, disposition: .immediateTask),
                fragment: InferenceEvidenceFragmenter.fragments(in: reference.evidenceText)[0],
                reference: reference) == nil)
    }

    private func reference() throws -> InferenceEvidenceReference {
        try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()],
                evidenceText: "Repair it now. Always review changes."))
    }
}
