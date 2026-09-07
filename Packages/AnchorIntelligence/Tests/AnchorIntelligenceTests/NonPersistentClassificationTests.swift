import AnchorDomain
import Testing

@testable import AnchorIntelligence

struct NonPersistentClassificationTests {
    @Test func currentTaskClassificationsNeverBecomeKnowledge() throws {
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()],
                evidenceText: "Repair the current failure."))
        let fragment = try #require(
            InferenceEvidenceFragmenter.fragments(in: reference.evidenceText).first)
        #expect(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(
                    fragmentNumber: fragment.number, disposition: .immediateTask),
                fragment: fragment, reference: reference) == nil)
    }
}
