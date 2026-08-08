public protocol KnowledgeEntryExtracting: Sendable {
    func extractKnowledgeEntrySummaries(fromSourceText sourceText: String) async throws -> [String]
}
