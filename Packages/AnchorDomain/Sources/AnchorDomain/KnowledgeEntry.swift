import Foundation

public struct KnowledgeEntry: Sendable, Hashable, Codable, Identifiable {
    public let id: KnowledgeEntryID
    public let projectID: ProjectID
    public let kind: KnowledgeEntryKind
    public let summaryText: String
    public let source: KnowledgeEntrySource
    public let sourceContentHash: ContentHash
    public let origin: KnowledgeEntryOrigin
    public let supportingMessageIDs: [MessageID]
    public let state: KnowledgeEntryState
    public let createdAt: Date

    public init(
        id: KnowledgeEntryID,
        projectID: ProjectID,
        kind: KnowledgeEntryKind,
        summaryText: String,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        origin: KnowledgeEntryOrigin = .classified,
        supportingMessageIDs: [MessageID] = [],
        state: KnowledgeEntryState = .current,
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.summaryText = summaryText
        self.source = source
        self.sourceContentHash = sourceContentHash
        self.origin = origin
        self.supportingMessageIDs = supportingMessageIDs
        self.state = state
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case kind
        case summaryText
        case source
        case sourceContentHash
        case origin
        case supportingMessageIDs
        case state
        case createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decode(KnowledgeEntryID.self, forKey: .id),
            projectID: try container.decode(ProjectID.self, forKey: .projectID),
            kind: try container.decode(KnowledgeEntryKind.self, forKey: .kind),
            summaryText: try container.decode(String.self, forKey: .summaryText),
            source: try container.decode(KnowledgeEntrySource.self, forKey: .source),
            sourceContentHash: try container.decode(ContentHash.self, forKey: .sourceContentHash),
            origin: try container.decodeIfPresent(KnowledgeEntryOrigin.self, forKey: .origin)
                ?? .classified,
            supportingMessageIDs: try container.decodeIfPresent(
                [MessageID].self, forKey: .supportingMessageIDs)
                ?? [],
            state: try container.decode(KnowledgeEntryState.self, forKey: .state),
            createdAt: try container.decode(Date.self, forKey: .createdAt)
        )
    }
}
