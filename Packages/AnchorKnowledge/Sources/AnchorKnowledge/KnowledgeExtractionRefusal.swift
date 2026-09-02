import AnchorDomain
import Foundation

public struct KnowledgeExtractionRefusal: Error, Sendable, CustomStringConvertible {
    public let extractedEntries: [KnowledgeEntry]
    public let descriptions: [String]

    public init(extractedEntries: [KnowledgeEntry], descriptions: [String]) {
        self.extractedEntries = extractedEntries
        self.descriptions = descriptions
    }

    public var description: String { descriptions.joined(separator: "; ") }
}
