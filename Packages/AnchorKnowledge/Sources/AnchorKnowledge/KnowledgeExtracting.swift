import AnchorDomain
import Foundation

public struct KnowledgeExtractionRequest: Sendable, Hashable {
    public let text: String
    public let projectID: ProjectID
    public let source: KnowledgeEntrySource
    public let sourceContentHash: ContentHash
    public let extractedAt: Date

    public init(
        text: String,
        projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        extractedAt: Date
    ) {
        self.text = text
        self.projectID = projectID
        self.source = source
        self.sourceContentHash = sourceContentHash
        self.extractedAt = extractedAt
    }
}

public protocol KnowledgeExtracting: Sendable {
    func extractEntries(for request: KnowledgeExtractionRequest) async throws -> [KnowledgeEntry]
}

public protocol KnowledgeStore: Sendable {
    func recordEntries(
        _ entries: [KnowledgeEntry], supersedingEntriesFrom source: KnowledgeEntrySource
    ) async throws
    func entries(
        forProject projectID: ProjectID, includingSuperseded: Bool
    ) async throws -> [KnowledgeEntry]
}
