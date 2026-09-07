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
        guard case .conversation(let conversationMessages) = request.content else {
            return []
        }

        let authorizedUnits = ConversationAuthoritySelector().authorizedUnits(
            in: conversationMessages)
        let authorizedWindow = AuthorizedInferenceWindow(
            units: authorizedUnits,
            characterBudget: characterBudget)

        let evidenceReferences = authorizedWindow.evidenceReferences
        guard !evidenceReferences.isEmpty else { return [] }

        switch await inference.readiness() {
        case .ready:
            break
        case .unavailable(let description):
            throw KnowledgeInferenceUnavailable(description: description)
        }

        let candidateStatements = try await inference.inferStatements(
            for: InferenceRequest(
                window: authorizedWindow.inferenceWindow,
                kinds: Self.askedKinds,
                evidenceReferences: evidenceReferences))
        let assessment = InferredStatementEvidenceValidator().assess(
            candidateStatements,
            in: authorizedWindow)

        return assessment.acceptedStatements.compactMap { entry(from: $0, for: request) }
    }

    private static let askedKinds = KnowledgeEntryKind.allCases.map(\.rawValue)

    private func entry(
        from statement: InferredStatement, for request: KnowledgeExtractionRequest
    ) -> KnowledgeEntry? {
        guard let kind = KnowledgeEntryKind(rawValue: statement.kind) else { return nil }

        return KnowledgeEntry(
            id: KnowledgeEntryID.derived(
                fromSeed: Self.entryIdentitySeed(
                    sourceContentHash: request.sourceContentHash,
                    kind: kind,
                    summaryText: statement.summaryText,
                    supportingMessageIDs: statement.supportingMessageIDs)),
            projectID: request.projectID,
            kind: kind,
            summaryText: statement.summaryText,
            source: request.source,
            sourceContentHash: request.sourceContentHash,
            origin: .inferred,
            supportingMessageIDs: statement.supportingMessageIDs,
            createdAt: request.extractedAt
        )
    }

    private static func entryIdentitySeed(
        sourceContentHash: ContentHash,
        kind: KnowledgeEntryKind,
        summaryText: String,
        supportingMessageIDs: [MessageID]
    ) -> String {
        let identityComponents =
            [
                sourceContentHash.rawValue,
                kind.rawValue,
                summaryText,
            ] + supportingMessageIDs.map(\.rawValue)

        return "inferred/"
            + identityComponents.map { identityComponent in
                "\(identityComponent.utf8.count):\(identityComponent)"
            }.joined()
    }
}
