import AnchorDomain
import Foundation

public struct CompositeKnowledgeExtractor: KnowledgeExtracting {
    private let extractors: [any KnowledgeExtracting]

    public init(_ extractors: [any KnowledgeExtracting]) {
        self.extractors = extractors
    }

    public func extractEntries(
        for request: KnowledgeExtractionRequest
    ) async throws -> [KnowledgeEntry] {
        var entries: [KnowledgeEntry] = []
        var seen: Set<KnowledgeEntryID> = []
        var refusals: [String] = []

        for extractor in extractors {
            do {
                for entry in try await extractor.extractEntries(for: request)
                where seen.insert(entry.id).inserted {
                    entries.append(entry)
                }
            } catch {
                refusals.append(String(describing: error))
            }
        }

        guard refusals.isEmpty else {
            throw KnowledgeExtractionRefusal(
                extractedEntries: entries,
                descriptions: refusals
            )
        }

        return entries
    }
}
