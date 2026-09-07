import AnchorDomain
import Foundation

public enum KnowledgeExtractionContent: Sendable, Hashable {
    case text(String)
    case conversation([ConversationMessage])

    public var text: String {
        switch self {
        case .text(let text):
            return text
        case .conversation(let messages):
            return messages.map { "\($0.role.rawValue): \($0.content)" }
                .joined(separator: "\n")
        }
    }
}

public struct KnowledgeExtractionRequest: Sendable, Hashable {
    public let content: KnowledgeExtractionContent
    public let projectID: ProjectID
    public let source: KnowledgeEntrySource
    public let sourceContentHash: ContentHash
    public let extractedAt: Date

    public var text: String { content.text }

    public init(
        text: String,
        projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        extractedAt: Date
    ) {
        content = .text(text)
        self.projectID = projectID
        self.source = source
        self.sourceContentHash = sourceContentHash
        self.extractedAt = extractedAt
    }

    public init(
        messages: [ConversationMessage],
        projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        extractedAt: Date
    ) {
        content = .conversation(messages)
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
