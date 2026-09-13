import AnchorDomain
import Foundation
import FoundationModels

public struct OnDeviceStatementInference: StatementInferring {
    public init() {}

    public func readiness() async -> InferenceReadiness {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            return .unavailable("\(reason)")
        }
    }

    public func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        guard !request.window.text.isEmpty, !request.evidenceReferences.isEmpty else { return [] }

        try Self.requireUniqueReferenceNumbers(request.evidenceReferences)
        try requireAvailableInference(await readiness())

        var statements: [InferredStatement] = []
        for reference in request.evidenceReferences {
            let intentSession = LanguageModelSession(
                instructions: TwoStageInferenceInstructions.referenceIntentInstructions(
                    for: reference))
            let intentDraft = try await intentSession.respond(
                to: Self.prompt(references: [reference]), generating: ReferenceIntentDraft.self,
                options: GenerationOptions(sampling: .greedy))
            let referenceIntent = try InferenceClaimEligibility.referenceIntent(
                from: intentDraft.content, expectedReferenceNumber: reference.number)
            let fragments = InferenceEvidenceFragmenter.fragments(in: reference.evidenceText)
            var eligibleClaims: [EligibleInferenceClaim] = []
            var referenceIncludesImmediateTask = false
            for fragment in fragments {
                let eligibility: FragmentEligibilityDraft
                do {
                    let session = LanguageModelSession(
                        instructions: TwoStageInferenceInstructions.eligibilityInstructions(
                            for: reference))
                    eligibility = try await session.respond(
                        to: InferenceClaimEligibility.prompt(
                            for: fragment, reference: reference),
                        generating: FragmentEligibilityDraft.self,
                        options: GenerationOptions(sampling: .greedy)
                    ).content
                } catch let LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(
                    errorContext)
                {
                    guard
                        let precedingFragment = InferenceEvidenceFragmenter.precedingFragment(
                            for: fragment, among: fragments)
                    else {
                        throw LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(
                            errorContext)
                    }
                    let retrySession = LanguageModelSession(
                        instructions: TwoStageInferenceInstructions.eligibilityInstructions(
                            for: reference))
                    eligibility = try await retrySession.respond(
                        to: InferenceClaimEligibility.prompt(
                            for: fragment, reference: reference,
                            precedingLanguageContext: precedingFragment.text),
                        generating: FragmentEligibilityDraft.self,
                        options: GenerationOptions(sampling: .greedy)
                    ).content
                }
                referenceIncludesImmediateTask =
                    referenceIncludesImmediateTask || eligibility.disposition == .immediateTask
                if let claim = try InferenceClaimEligibility.durableClaim(
                    from: eligibility, fragment: fragment, reference: reference)
                {
                    eligibleClaims.append(claim)
                }
            }
            for claim in eligibleClaims {
                let classifier = LanguageModelSession(
                    instructions: TwoStageInferenceInstructions.classification)
                let classification = try await classifier.respond(
                    to: ExtractiveDurableClaimClassification.prompt(for: claim),
                    generating: DurableKindTag.self,
                    options: GenerationOptions(sampling: .greedy))
                guard
                    ExtractiveDurableClaimClassification.kindIsPersistent(
                        classification.content.kind, within: referenceIntent,
                        referenceIncludesImmediateTask: referenceIncludesImmediateTask)
                else { continue }
                if classification.content.kind == .risk {
                    guard try await Self.containsExplicitHarm(in: claim) else { continue }
                }
                statements.append(
                    contentsOf: ExtractiveDurableClaimClassification.statements(
                        for: classification.content.kind,
                        claim: claim, kinds: request.kinds))
            }
        }

        return InferredStatement.usable(among: statements, amongKinds: request.kinds)
    }

    static func requireUniqueReferenceNumbers(_ references: [InferenceEvidenceReference]) throws {
        guard Set(references.map(\.number)).count == references.count else {
            throw InvalidInferenceResponse.duplicateReferenceNumbers
        }
    }

    private static func containsExplicitHarm(in claim: EligibleInferenceClaim) async throws -> Bool
    {
        let candidates = explicitHarmCandidates(in: claim.evidenceText)
        for candidate in candidates {
            let verifier = LanguageModelSession(
                instructions: TwoStageInferenceInstructions.explicitHarmVerification)
            let verification = try await verifier.respond(
                to: ExtractiveDurableClaimClassification.explicitHarmPrompt(for: candidate),
                generating: ExplicitHarmTag.self,
                options: GenerationOptions(sampling: .greedy))
            guard Self.isVerifiedExplicitHarm(verification.content, in: candidate) else { continue }
            let confirmationSession = LanguageModelSession(
                instructions: TwoStageInferenceInstructions.explicitHarmConfirmation)
            let confirmation = try await confirmationSession.respond(
                to: ExtractiveDurableClaimClassification.explicitHarmConfirmationPrompt(
                    selectedClaim: candidate,
                    harmfulOutcomeText: verification.content.harmfulOutcomeText,
                    possibilityOrFailureText: verification.content.possibilityOrFailureText),
                generating: ExplicitHarmConfirmationTag.self,
                options: GenerationOptions(sampling: .greedy))
            if confirmation.content.outcomeKind == .harmOrFailure,
                confirmation.content.relationKind == .possibilityOrFailure
            {
                return true
            }
        }
        return false
    }

    static func explicitHarmCandidates(in selectedClaim: String) -> [String] {
        let quotedLines = InferenceEvidenceFragmenter.markdownQuoteLines(in: selectedClaim)
        return quotedLines + [selectedClaim]
    }

    static func isVerifiedExplicitHarm(
        _ verification: ExplicitHarmTag, in selectedClaim: String
    ) -> Bool {
        guard verification.presence == .present else { return false }
        let harmfulOutcomeText = verification.harmfulOutcomeText.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let possibilityOrFailureText = verification.possibilityOrFailureText.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !harmfulOutcomeText.isEmpty, !possibilityOrFailureText.isEmpty else { return false }
        return containsOrderedLiteralWords(harmfulOutcomeText, in: selectedClaim)
            && containsOrderedLiteralWords(possibilityOrFailureText, in: selectedClaim)
    }

    private static func containsOrderedLiteralWords(
        _ extractedText: String, in selectedClaim: String
    ) -> Bool {
        let extractedWords = extractedText.lowercased().components(
            separatedBy: CharacterSet.alphanumerics.inverted
        ).filter { !$0.isEmpty }
        let claimWords = selectedClaim.lowercased().components(
            separatedBy: CharacterSet.alphanumerics.inverted
        ).filter { !$0.isEmpty }
        guard !extractedWords.isEmpty else { return false }

        var nextClaimIndex = claimWords.startIndex
        for extractedWord in extractedWords {
            guard
                let matchingIndex = claimWords[nextClaimIndex...].firstIndex(of: extractedWord)
            else { return false }
            nextClaimIndex = claimWords.index(after: matchingIndex)
        }
        return true
    }

    private struct EvidencePromptEntry: Encodable {
        let number: Int
        let evidence: String
        let confirmation: String?
    }

    static func prompt(references: [InferenceEvidenceReference]) throws -> String {
        let entries = references.map { reference in
            EvidencePromptEntry(
                number: reference.number, evidence: reference.evidenceText,
                confirmation: reference.confirmationText)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(entries), as: UTF8.self)
    }

}

enum InvalidInferenceResponse: Error, Equatable {
    case duplicateReferenceNumbers
}

func requireAvailableInference(_ readiness: InferenceReadiness) throws {
    switch readiness {
    case .ready:
        return
    case .unavailable(let description):
        throw StatementInferenceUnavailable(description: description)
    }
}
