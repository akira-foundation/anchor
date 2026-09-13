import AnchorDomain
import Foundation
import Testing

@testable import AnchorIntelligence

@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["ANCHOR_INFERENCE_TESTS"] != nil), .serialized)
struct ReferencedStatementInferenceLiveTests {
    @Test(
        "isolated routine messages do not become knowledge",
        arguments: [
            "Good morning. Thanks for your help.",
            "The tests passed. The build succeeded.",
            "Please run the tests and open a pull request.",
            "What should we do next?",
        ])
    func isolatedRoutineMessagesDoNotBecomeKnowledge(_ text: String) async throws {
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()], evidenceText: text))
        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: text, keeping: 100),
                kinds: KnowledgeEntryKind.allCases.map(\.rawValue), evidenceReferences: [reference])
        )

        #expect(statements.isEmpty)
    }

    @Test("an isolated confirmed proposal retains its decision and risk")
    func isolatedConfirmedProposalRetainsDecisionAndRisk() async throws {
        let proposalID = MessageID()
        let confirmationID = MessageID()
        let evidence = "Keep the journal local. An unbounded journal can exhaust disk space."
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [proposalID, confirmationID],
                evidenceText: evidence, confirmationText: "Approved"))
        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: evidence, keeping: 100),
                kinds: KnowledgeEntryKind.allCases.map(\.rawValue), evidenceReferences: [reference])
        )

        #expect(statements.map(\.kind).sorted() == ["decision", "risk"])
        #expect(
            statements.map(\.supportingMessageIDs) == [
                [proposalID, confirmationID], [proposalID, confirmationID],
            ])
    }

    @Test("one indivisible multi-kind fragment preserves explicit risk by priority")
    func indivisibleFragmentPreservesExplicitRiskByPriority() async throws {
        let evidence =
            "Keep the journal local; without a size limit it could exhaust device storage."
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID(), MessageID()],
                evidenceText: evidence, confirmationText: "Approved"))

        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: evidence, keeping: 100),
                kinds: KnowledgeEntryKind.allCases.map(\.rawValue),
                evidenceReferences: [reference]))

        #expect(statements.map(\.kind) == ["risk"])
        #expect(statements.allSatisfy { $0.evidenceText == evidence })
    }

    @Test("mixed references retain a confirmed decision, its risk, and a behavior preference")
    func mixedReferencesRetainDecisionRiskAndPreference() async throws {
        let proposalID = MessageID()
        let confirmationID = MessageID()
        let preferenceID = MessageID()
        let references = [
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()],
                evidenceText: "Good morning. Thanks for your help.")!,
            InferenceEvidenceReference(
                number: 2,
                supportingMessageIDs: [proposalID, confirmationID],
                evidenceText:
                    "Keep the journal local. An unbounded journal can exhaust disk space.",
                confirmationText: "Approved")!,
            InferenceEvidenceReference(
                number: 3, supportingMessageIDs: [preferenceID],
                evidenceText: "Always respond in Portuguese from now on.")!,
            InferenceEvidenceReference(
                number: 4, supportingMessageIDs: [MessageID()],
                evidenceText: "The tests passed. The build succeeded.")!,
            InferenceEvidenceReference(
                number: 5, supportingMessageIDs: [MessageID()],
                evidenceText: "Please run the tests and open a pull request.")!,
            InferenceEvidenceReference(
                number: 6, supportingMessageIDs: [MessageID()],
                evidenceText: "What should we do next?")!,
        ]
        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: "authorized references", keeping: 100),
                kinds: KnowledgeEntryKind.allCases.map(\.rawValue), evidenceReferences: references))

        #expect(statements.count == 3)
        #expect(
            Set(statements.filter { $0.kind == "decision" }.flatMap(\.supportingMessageIDs)) == [
                proposalID, confirmationID, preferenceID,
            ])
        #expect(
            statements.filter { $0.kind == "risk" }.map(\.supportingMessageIDs) == [
                [proposalID, confirmationID]
            ])
        #expect(statements.allSatisfy { ["decision", "risk"].contains($0.kind) })
    }
}
