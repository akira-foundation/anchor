import AnchorDomain
import AnchorIntelligence
import Foundation
import Testing

@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["ANCHOR_INFERENCE_TESTS"] != nil), .serialized)
struct DurableKnowledgeKindsLiveTests {
    @Test(arguments: [
        (
            "Keep CSV export in the backlog for the next milestone; do not implement it today.",
            "todo"
        ),
        (
            "Leave the choice of encryption provider unresolved until the security review next month.",
            "question"
        ),
        (
            "The product consists of an offline editor, a local SQLite repository, and a background synchronization service.",
            "architecture"
        ),
        (
            "This product is a private reading journal for researchers to collect sources and track reading progress across their devices.",
            "summary"
        ),
        ("Always use metric units in every future report.", "decision"),
        (
            "Without an upper size limit, cached attachments could exhaust the device storage.",
            "risk"
        ),
    ])
    func preservesExplicitDurableKnowledge(_ example: (String, String)) async throws {
        let reference = try #require(
            InferenceEvidenceReference(
                number: 1, supportingMessageIDs: [MessageID()], evidenceText: example.0))
        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: example.0, keeping: 3000),
                kinds: KnowledgeEntryKind.allCases.map(\.rawValue), evidenceReferences: [reference])
        )
        #expect(statements.map(\.kind) == [example.1])
        #expect(statements.map(\.supportingMessageIDs) == [reference.supportingMessageIDs])
        #expect(statements.map(\.evidenceText) == [example.0])
    }
}
