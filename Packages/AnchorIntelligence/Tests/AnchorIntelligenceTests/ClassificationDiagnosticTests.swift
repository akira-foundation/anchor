import AnchorDomain
import Foundation
import FoundationModels
import Testing

@testable import AnchorIntelligence

@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["ANCHOR_CLASSIFICATION_DIAGNOSTIC"] != nil),
    .serialized)
struct ClassificationDiagnosticTests {
    @Test func inspectEligibilityGenerationSchema() {
        print(
            "intent-generation-schema=\(ReferenceIntentDraft.generationSchema.debugDescription)"
        )
        print(
            "eligibility-generation-schema=\(FragmentEligibilityDraft.generationSchema.debugDescription)"
        )
        print(
            "kind-generation-schema=\(DurableKindTag.generationSchema.debugDescription)"
        )
    }

    @Test func inspectSyntheticClaimEligibility() async throws {
        let examples = [
            "ok, mas vc vai trabalhar em paralelo com todos os revisores disponiveis, e nunca em um documento soh\n\n",
            "The calendar tests cannot start because the dependency lockfile is stale. Update it and run the tests now. From now on, always require independent review before merging any change.",
            "o q vc acha de toda vez q terminar uma reunião mandarmos logo um resumo por email ?",
            "This product is a private reading journal for researchers to collect sources and track reading progress across their devices.",
            "Revised policy:\n> Ask before each major release.\n> Never publish automatically.\nDo patches count?",
        ]
        for (index, example) in examples.enumerated() {
            let reference = try #require(
                InferenceEvidenceReference(
                    number: 1, supportingMessageIDs: [MessageID()], evidenceText: example))
            let intent = try await LanguageModelSession(
                instructions: TwoStageInferenceInstructions.referenceIntent
            ).respond(
                to: OnDeviceStatementInference.prompt(references: [reference]),
                generating: ReferenceIntentDraft.self,
                options: GenerationOptions(sampling: .greedy))
            print("synthetic-intent example=\(index) response=\(intent.rawContent.jsonString)")
            for fragment in InferenceEvidenceFragmenter.fragments(in: example) {
                let eligibility = try await LanguageModelSession(
                    instructions: TwoStageInferenceInstructions.eligibility
                ).respond(
                    to: InferenceClaimEligibility.prompt(for: fragment, reference: reference),
                    generating: FragmentEligibilityDraft.self,
                    options: GenerationOptions(sampling: .greedy))
                print(
                    "synthetic-eligibility example=\(index) fragment=\(fragment.number) response=\(eligibility.rawContent.jsonString)"
                )
            }
        }
    }

    @Test func compareStructuredAndPlainClassification() async throws {
        let examples = [
            "The tests passed. The build succeeded.",
            "Please run the tests and open a pull request.",
            "What should we do next?",
            "Always respond in Portuguese from now on.",
            "Keep the journal local. An unbounded journal can exhaust disk space. The user approved this proposal.",
        ]
        for (index, example) in examples.enumerated() {
            let session = LanguageModelSession()
            let quoted = String(decoding: try JSONEncoder().encode(example), as: UTF8.self)
            let reply = try await session.respond(
                to: """
                    Classify this sentence as REPORT, QUESTION, REQUEST, PREFERENCE, or DECISION:
                    \(quoted)
                    Return the label only.
                    """, options: GenerationOptions(sampling: .greedy))
            print(
                "classification-diagnostic example=\(index) purpose=\(reply.content) raw=\(reply.rawContent.jsonString)"
            )
            if reply.content.trimmingCharacters(in: .whitespacesAndNewlines) == "REQUEST" {
                let duration = try await LanguageModelSession().respond(
                    to: """
                        Instruction: \(quoted)
                        Does this instruction apply repeatedly in the future, or just to the current task?
                        Answer only REPEATED or CURRENT.
                        """, options: GenerationOptions(sampling: .greedy))
                print("classification-diagnostic example=\(index) duration=\(duration.content)")
            }
            let warning = try await LanguageModelSession().respond(
                to: """
                    Text: \(quoted)
                    Does this text explicitly mention a possible harmful outcome?
                    Answer only YES or NO.
                    """, options: GenerationOptions(sampling: .greedy))
            print("classification-diagnostic example=\(index) warning=\(warning.content)")
        }
    }
}
