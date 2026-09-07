import AnchorDomain
import AnchorIntelligence
import Foundation
import Testing

@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["ANCHOR_INFERENCE_TESTS"] != nil), .serialized)
struct UnsettledProposalLiveTests {
    @Test(arguments: [
        "o q vc acha de toda vez q terminar uma reunião mandarmos logo um resumo por email ?",
        "What do you think of publishing a summary after every meeting?",
        "nao tem de ser necessariamente anual... mensal tbm",
    ])
    func proposalsAndUnresolvedFragmentsAreNotSettledDecisions(_ text: String) async throws {
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()], evidenceText: text))
        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: text, keeping: 3000),
                kinds: KnowledgeEntryKind.allCases.map(\.rawValue), evidenceReferences: [reference])
        )
        #expect(statements.isEmpty)
    }
}
