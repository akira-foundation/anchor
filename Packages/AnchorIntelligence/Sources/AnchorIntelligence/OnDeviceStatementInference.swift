import Foundation
import FoundationModels

@Generable
struct InferredStatementDraft {
    @Guide(description: "One of the kinds the question listed, lowercase.")
    var kind: String

    @Guide(description: "What was decided, planned or risked, in one short sentence.")
    var summaryText: String
}

@Generable
struct InferredStatementDrafts {
    @Guide(
        description: "Only statements the conversation actually makes. Empty when it makes none.")
    var statements: [InferredStatementDraft]
}

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
        guard !request.window.text.isEmpty else { return [] }

        try requireAvailableInference(await readiness())

        let session = LanguageModelSession(instructions: Self.instructions(for: request.kinds))
        let drafts = try await session.respond(
            to: request.window.text, generating: InferredStatementDrafts.self)

        return InferredStatement.usable(
            among: drafts.content.statements.map {
                InferredStatement(kind: $0.kind, summaryText: $0.summaryText)
            },
            amongKinds: request.kinds
        )
    }

    private static func instructions(for kinds: [String]) -> String {
        """
        You read a transcript of a coding session between a person and an agent.
        Report only statements the transcript actually makes, using these kinds: \
        \(kinds.joined(separator: ", ")).
        Report nothing when the transcript states nothing of those kinds.
        Never infer intent that is not written down.
        """
    }
}

func requireAvailableInference(_ readiness: InferenceReadiness) throws {
    switch readiness {
    case .ready:
        return
    case .unavailable(let description):
        throw StatementInferenceUnavailable(description: description)
    }
}
