import Foundation

public struct KnowledgeEntry: Sendable, Hashable, Codable, Identifiable {
    public let id: KnowledgeEntryID
    public let projectID: ProjectID
    public let kind: KnowledgeEntryKind
    public let summaryText: String
    public let source: KnowledgeEntrySource
    public let sourceContentHash: ContentHash
    public let state: KnowledgeEntryState
    public let createdAt: Date

    public init(
        id: KnowledgeEntryID,
        projectID: ProjectID,
        kind: KnowledgeEntryKind,
        summaryText: String,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        state: KnowledgeEntryState = .current,
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.summaryText = summaryText
        self.source = source
        self.sourceContentHash = sourceContentHash
        self.state = state
        self.createdAt = createdAt
    }
}
