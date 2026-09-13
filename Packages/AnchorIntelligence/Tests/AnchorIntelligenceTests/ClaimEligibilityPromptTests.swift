import AnchorDomain
import Testing

@testable import AnchorIntelligence

struct ClaimEligibilityPromptTests {
    @Test func approvedReferenceCarriesExplicitAuthority() throws {
        let reference = try reference(confirmation: "sim")
        let instructions = TwoStageInferenceInstructions.eligibilityInstructions(for: reference)
        #expect(instructions.contains("The following is an APPROVED proposal"))
        #expect(instructions.hasPrefix(TwoStageInferenceInstructions.eligibility))
    }

    @Test func unapprovedReferenceDoesNotAcquireApproval() throws {
        let reference = try reference(confirmation: nil)
        #expect(
            TwoStageInferenceInstructions.eligibilityInstructions(for: reference)
                == TwoStageInferenceInstructions.eligibility)
    }

    private func reference(confirmation: String?) throws -> InferenceEvidenceReference {
        try #require(
            InferenceEvidenceReference(
                number: 3,
                supportingMessageIDs: confirmation == nil
                    ? [MessageID()] : [MessageID(), MessageID()],
                evidenceText: "Should we require review for every change?",
                confirmationText: confirmation))
    }
}
