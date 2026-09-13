import AnchorDomain
import Foundation
import Testing

@testable import AnchorIntelligence

struct CodeOwnedFragmentEligibilityTests {
    @Test func codeSplitsMixedEvidenceIntoNumberedLiteralFragments() {
        let evidence = """
            Repair it now. Always review changes.
            > Never skip regression tests.

            What next?
            """

        #expect(
            InferenceEvidenceFragmenter.fragments(in: evidence) == [
                .init(number: 1, text: "Repair it now."),
                .init(number: 2, text: "Always review changes."),
                .init(number: 3, text: "> Never skip regression tests."),
                .init(number: 4, text: "What next?"),
            ])
    }

    @Test func codeKeepsMarkdownPolicyBlockWithItsHeader() {
        let evidence = """
            Entendido.
            Revised policy:
            > Ask before each major release.
            > Never publish automatically.
            Do patches count?
            """

        #expect(
            InferenceEvidenceFragmenter.fragments(in: evidence) == [
                .init(number: 1, text: "Entendido."),
                .init(
                    number: 2,
                    text: """
                        Revised policy:
                        > Ask before each major release.
                        > Never publish automatically.
                        """),
                .init(number: 3, text: "Do patches count?"),
            ])
        #expect(
            InferenceEvidenceFragmenter.markdownQuoteLines(in: evidence) == [
                "Ask before each major release.", "Never publish automatically.",
            ])
        #expect(
            InferenceEvidenceFragmenter.markdownQuoteLines(
                in: "> Cached attachments could\n> exhaust device storage."
            ) == ["Cached attachments could exhaust device storage."])
    }

    @Test func modelSelectsCodeOwnedFragmentByNumber() throws {
        let reference = try reference()
        let fragments = InferenceEvidenceFragmenter.fragments(in: reference.evidenceText)
        let selected = try #require(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(fragmentNumber: 2, disposition: .durable),
                fragment: fragments[1], reference: reference))

        #expect(selected.number == 2)
        #expect(selected.evidenceText == "Always review changes.")
        #expect(selected.reference == reference)
    }

    @Test func rejectsWrongFragmentNumber() throws {
        let reference = try reference()
        let fragment = try #require(
            InferenceEvidenceFragmenter.fragments(in: reference.evidenceText).first)

        #expect(throws: InvalidClaimInferenceResponse.invalidReference) {
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(fragmentNumber: 99, disposition: .durable),
                fragment: fragment, reference: reference)
        }
    }

    @Test func rejectedFragmentDoesNotBecomeKnowledge() throws {
        let reference = try reference()
        let fragment = try #require(
            InferenceEvidenceFragmenter.fragments(in: reference.evidenceText).first)

        #expect(
            try InferenceClaimEligibility.durableClaim(
                from: FragmentEligibilityDraft(
                    fragmentNumber: fragment.number, disposition: .immediateTask),
                fragment: fragment, reference: reference) == nil)
    }

    @Test func primaryPromptExcludesUnselectedReferenceText() throws {
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID(), MessageID()],
                evidenceText: "Repair it now. Always review changes.",
                confirmationText: "Approved"))
        let fragment = try #require(
            InferenceEvidenceFragmenter.fragments(in: reference.evidenceText).last)
        let prompt = try InferenceClaimEligibility.prompt(for: fragment, reference: reference)
        let fields = try #require(
            JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])

        #expect(
            Set(fields.keys) == [
                "confirmation", "referenceNumber", "selectedFragment", "selectedFragmentNumber",
            ])
        #expect(fields["selectedFragment"] as? String == "Always review changes.")
        #expect(!(prompt.contains("Repair it now")))
    }

    @Test func unsupportedShortFragmentKeepsItsPredecessorAsSeparateLanguageContext() throws {
        let evidence = "The current installation fails. Bloqueia a suite local. Fix it now."
        let fragments = InferenceEvidenceFragmenter.fragments(in: evidence)
        let selected = try #require(fragments.first { $0.number == 2 })
        let predecessor = try #require(
            InferenceEvidenceFragmenter.precedingFragment(for: selected, among: fragments))
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()], evidenceText: evidence))
        let prompt = try InferenceClaimEligibility.prompt(
            for: selected, reference: reference, precedingLanguageContext: predecessor.text)
        let fields = try #require(
            JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])

        #expect(predecessor == .init(number: 1, text: "The current installation fails."))
        #expect(fields["selectedFragment"] as? String == "Bloqueia a suite local.")
        #expect(fields["precedingLanguageContext"] as? String == "The current installation fails.")
        #expect(fields["selectedFragmentNumber"] as? Int == 2)
    }

    @Test func validatesReferenceIntentNumber() throws {
        #expect(
            try InferenceClaimEligibility.referenceIntent(
                from: ReferenceIntentDraft(referenceNumber: 4, intent: .currentWork),
                expectedReferenceNumber: 4) == .currentWork)
        #expect(throws: InvalidClaimInferenceResponse.invalidReference) {
            try InferenceClaimEligibility.referenceIntent(
                from: ReferenceIntentDraft(referenceNumber: 7, intent: .mixed),
                expectedReferenceNumber: 4)
        }
    }

    private func reference() throws -> InferenceEvidenceReference {
        try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()],
                evidenceText: "Repair it now. Always review changes."))
    }
}
