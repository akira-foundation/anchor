import AnchorDomain
import AnchorFoundation
import AnchorIntelligence
import Foundation

public struct InferredKnowledgeExtractor: KnowledgeExtracting {
    private let inference: any StatementInferring
    private let characterBudget: Int

    public init(
        inference: any StatementInferring,
        characterBudget: Int = InferenceWindow.defaultCharacterBudget
    ) {
        self.inference = inference
        self.characterBudget = characterBudget
    }

    public func extractEntries(
        for request: KnowledgeExtractionRequest
    ) async throws -> [KnowledgeEntry] {
        switch await inference.readiness() {
        case .ready:
            break
        case .unavailable(let description):
            throw KnowledgeInferenceUnavailable(description: description)
        }

        let window = InferenceWindow(over: request.text, keeping: characterBudget)
        let statements = try await inference.inferStatements(
            for: InferenceRequest(window: window, kinds: Self.askedKinds))

        return InferredStatement.usable(among: statements, amongKinds: Self.askedKinds)
            .compactMap { entry(from: $0, for: request) }
    }

    private static let askedKinds = KnowledgeEntryKind.allCases.map(\.rawValue)

    private func entry(
        from statement: InferredStatement, for request: KnowledgeExtractionRequest
    ) -> KnowledgeEntry? {
        guard let kind = KnowledgeEntryKind(rawValue: statement.kind) else { return nil }

        return KnowledgeEntry(
            id: KnowledgeEntryID.derived(
                fromSeed:
                    "inferred/\(request.sourceContentHash.rawValue)/\(kind.rawValue)/\(statement.summaryText)"
            ),
            projectID: request.projectID,
            kind: kind,
            summaryText: statement.summaryText,
            source: request.source,
            sourceContentHash: request.sourceContentHash,
            origin: .inferred,
            createdAt: request.extractedAt
        )
    }
}
