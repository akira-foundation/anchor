import AnchorDomain

public protocol KnowledgeContextReading: Sendable {
    func listCurrentKnowledge(
        forProject projectID: ProjectID,
        kind: KnowledgeEntryKind?,
        origin: KnowledgeEntryOrigin?,
        page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<KnowledgeEntry>

    func loadCurrentKnowledge(
        withIdentifier knowledgeEntryID: KnowledgeEntryID,
        forProject projectID: ProjectID
    ) async throws -> KnowledgeEntry?
}
