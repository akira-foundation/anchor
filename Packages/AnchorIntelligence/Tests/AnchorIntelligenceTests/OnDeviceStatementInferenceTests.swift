import Foundation
import Testing

@testable import AnchorIntelligence

private let liveInferenceIsAllowed =
    ProcessInfo.processInfo.environment["ANCHOR_INFERENCE_TESTS"] != nil

@Suite("Asking the machine's own model")
struct OnDeviceStatementInferenceTests {
    @Test("a conversation with nothing in it is not asked about")
    func conversationWithNothingInItIsNotAskedAbout() async throws {
        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(over: "", keeping: 1_000), kinds: ["decision"]))

        #expect(statements.isEmpty)
    }

    @Test("an unavailable model is a refusal rather than an empty answer")
    func unavailableModelIsRefusalRatherThanEmptyAnswer() {
        #expect(throws: StatementInferenceUnavailable.self) {
            try requireAvailableInference(.unavailable("model is preparing"))
        }
    }
}

@Suite(
    "Asking the machine's own model, for real",
    .enabled(if: liveInferenceIsAllowed), .serialized
)
struct OnDeviceStatementInferenceLiveTests {
    private let kinds = ["decision", "todo", "risk", "question"]

    @Test("a machine that can answer says it is ready")
    func machineThatCanAnswerSaysItIsReady() async throws {
        #expect(await OnDeviceStatementInference().readiness() == .ready)
    }

    @Test("a decision stated in the conversation is reported as a decision")
    func decisionStatedInConversationIsReportedAsDecision() async throws {
        let conversation = """
            user: where should the operation journal live?
            assistant: we decided to keep the operation journal on the local disk only, \
            because sending it to iCloud would duplicate what the revision feed already carries.
            """

        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(
                    over: conversation, keeping: InferenceWindow.defaultCharacterBudget),
                kinds: kinds))

        #expect(statements.contains { $0.kind == "decision" })
        #expect(statements.allSatisfy { kinds.contains($0.kind) })
    }

    @Test("a conversation about nothing in particular reports nothing in particular")
    func conversationAboutNothingInParticularReportsNothingInParticular() async throws {
        let conversation = """
            user: good morning
            assistant: good morning
            user: thanks
            """

        let statements = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(
                window: InferenceWindow(
                    over: conversation, keeping: InferenceWindow.defaultCharacterBudget),
                kinds: kinds))

        #expect(statements.isEmpty)
    }

    @Test("the default window fits in the window the model actually has")
    func defaultWindowFitsInWindowModelActuallyHas() async throws {
        let sentences = [
            "user: where should the operation journal live?",
            "assistant: we decided to keep it on local disk only.",
            "user: what did the tests say?",
            "assistant: four hundred and eighty six passed, none failed.",
            "user: and the checkpoint?",
            "assistant: it now waits for the recording to succeed first.",
        ]
        let conversation = (0..<400).map { sentences[$0 % sentences.count] }
            .joined(separator: "\n")
        let window = InferenceWindow(
            over: conversation, keeping: InferenceWindow.defaultCharacterBudget)

        #expect(window.text.count == InferenceWindow.defaultCharacterBudget)

        _ = try await OnDeviceStatementInference().inferStatements(
            for: InferenceRequest(window: window, kinds: kinds))
    }
}
