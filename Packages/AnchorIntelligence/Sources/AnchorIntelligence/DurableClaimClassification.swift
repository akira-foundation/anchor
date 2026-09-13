import Foundation
import FoundationModels

@Generable
enum DurableKnowledgeKind: String, CaseIterable {
    case decision, risk, summary, todo, question, architecture
}

@Generable
struct DurableKindTag {
    @Guide(
        description:
            "The highest-priority durable kind explicitly supported by selectedClaim.")
    var kind: DurableKnowledgeKind
}

@Generable
enum ExplicitHarmPresence: String {
    case absent, present
}

@Generable
struct ExplicitHarmTag {
    @Guide(
        description:
            "present only when selectedClaim itself names a potential harmful outcome or failure; a prohibition or safeguard without a named harm is absent"
    )
    var presence: ExplicitHarmPresence

    @Guide(
        description:
            "Exact words from selectedClaim that name the harmful outcome or failure; empty when presence is absent"
    )
    var harmfulOutcomeText: String

    @Guide(
        description:
            "Exact words from selectedClaim that state possibility, risk, or failure; empty when presence is absent"
    )
    var possibilityOrFailureText: String
}

@Generable
enum ExtractedOutcomeKind: String {
    case harmOrFailure
    case neutralOrSafeguard
}

@Generable
enum ExtractedRelationKind: String {
    case possibilityOrFailure
    case ordinaryAction
}

@Generable
struct ExplicitHarmConfirmationTag {
    var outcomeKind: ExtractedOutcomeKind
    var relationKind: ExtractedRelationKind
}

enum ExtractiveDurableClaimClassification {
    static func kindIsPersistent(
        _ kind: DurableKnowledgeKind, within referenceIntent: ReferenceIntent,
        referenceIncludesImmediateTask: Bool
    ) -> Bool {
        switch referenceIntent {
        case .tentativeProposal, .executionReport, .ordinaryConversation:
            false
        case .currentWork:
            !referenceIncludesImmediateTask || kind == .decision
        case .approvedProposal:
            [.decision, .risk, .todo, .question].contains(kind)
        case .standingPolicy:
            kind == .decision
        case .durableKnowledge, .mixed:
            true
        }
    }

    static func statements(
        for kind: DurableKnowledgeKind, claim: EligibleInferenceClaim, kinds: [String]
    ) -> [InferredStatement] {
        return InferredStatement.usable(
            among: [
                claim.reference.statement(
                    kind: kind.rawValue, summaryText: claim.evidenceText)
            ], amongKinds: kinds)
    }

    static func prompt(for claim: EligibleInferenceClaim) throws -> String {
        let prompt = ExtractiveClassificationPrompt(
            claimNumber: claim.number, selectedClaim: claim.evidenceText,
            confirmation: claim.reference.confirmationText)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(prompt), as: UTF8.self)
    }

    static func explicitHarmPrompt(for selectedClaim: String) throws -> String {
        let prompt = ExplicitHarmPrompt(selectedClaim: selectedClaim)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(prompt), as: UTF8.self)
    }

    static func explicitHarmConfirmationPrompt(
        selectedClaim: String, harmfulOutcomeText: String, possibilityOrFailureText: String
    ) throws -> String {
        let prompt = ExplicitHarmConfirmationPrompt(
            selectedClaim: selectedClaim, outcomeText: harmfulOutcomeText,
            relationText: possibilityOrFailureText)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(prompt), as: UTF8.self)
    }

}

private struct ExplicitHarmConfirmationPrompt: Encodable {
    let selectedClaim: String
    let outcomeText: String
    let relationText: String
}

private struct ExtractiveClassificationPrompt: Encodable {
    let claimNumber: Int
    let selectedClaim: String
    let confirmation: String?
}

private struct ExplicitHarmPrompt: Encodable {
    let selectedClaim: String
}
