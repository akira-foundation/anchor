import Foundation
import FoundationModels

@Generable
enum ClaimDisposition: String {
    case durable, immediateTask, tentativeProposal, executionReport
    case ordinaryQuestion, insufficientContext, conversation
}

@Generable
enum ReferenceIntent: String {
    case currentWork, tentativeProposal, approvedProposal, standingPolicy
    case executionReport, ordinaryConversation, durableKnowledge, mixed
}

@Generable
struct ReferenceIntentDraft {
    @Guide(description: "Copy the supplied reference number exactly.")
    var referenceNumber: Int
    @Guide(description: "The overall intent of the complete reference.")
    var intent: ReferenceIntent
}

@Generable
struct FragmentEligibilityDraft {
    @Guide(description: "Copy selectedFragmentNumber exactly.")
    var fragmentNumber: Int
    @Guide(
        description:
            "Classify only selectedFragment. Conditional policy language such as 'would be' or 'seria' is tentativeProposal unless confirmation is non-null. An explicit enduring product purpose or an issue explicitly left unresolved until a named future review is durable, not conversation or tentativeProposal."
    )
    var disposition: ClaimDisposition
}

struct EligibleInferenceClaim {
    let number: Int
    let evidenceText: String
    let reference: InferenceEvidenceReference

    fileprivate init(number: Int, evidenceText: String, reference: InferenceEvidenceReference) {
        self.number = number
        self.evidenceText = evidenceText
        self.reference = reference
    }
}

enum InvalidClaimInferenceResponse: Error {
    case invalidReference
}

enum InferenceClaimEligibility {
    static func referenceIntent(
        from draft: ReferenceIntentDraft, expectedReferenceNumber: Int
    ) throws -> ReferenceIntent {
        guard draft.referenceNumber == expectedReferenceNumber else {
            throw InvalidClaimInferenceResponse.invalidReference
        }
        return draft.intent
    }

    static func durableClaim(
        from draft: FragmentEligibilityDraft, fragment: InferenceEvidenceFragment,
        reference: InferenceEvidenceReference
    ) throws -> EligibleInferenceClaim? {
        guard draft.fragmentNumber == fragment.number else {
            throw InvalidClaimInferenceResponse.invalidReference
        }
        guard draft.disposition == .durable else { return nil }
        return EligibleInferenceClaim(
            number: fragment.number, evidenceText: fragment.text, reference: reference)
    }

    static func prompt(
        for fragment: InferenceEvidenceFragment, reference: InferenceEvidenceReference,
        precedingLanguageContext: String? = nil
    ) throws -> String {
        let prompt = FragmentEligibilityPrompt(
            referenceNumber: reference.number, selectedFragmentNumber: fragment.number,
            selectedFragment: fragment.text, precedingLanguageContext: precedingLanguageContext,
            confirmation: reference.confirmationText)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(prompt), as: UTF8.self)
    }

}

private struct FragmentEligibilityPrompt: Encodable {
    let referenceNumber: Int
    let selectedFragmentNumber: Int
    let selectedFragment: String
    let precedingLanguageContext: String?
    let confirmation: String?
}
