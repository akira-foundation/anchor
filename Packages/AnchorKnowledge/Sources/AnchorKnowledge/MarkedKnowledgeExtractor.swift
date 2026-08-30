import AnchorDomain
import AnchorFoundation
import Foundation

public struct MarkedKnowledgeExtractor: KnowledgeExtracting {
    public static let markers: [(marker: String, kind: KnowledgeEntryKind)] = [
        ("TODO:", .todo),
        ("FIXME:", .todo),
        ("DECISION:", .decision),
        ("DECIDED:", .decision),
        ("QUESTION:", .question),
        ("RISK:", .risk),
        ("ARCHITECTURE:", .architecture),
        ("SUMMARY:", .summary),
    ]

    public init() {}

    public func extractEntries(
        for request: KnowledgeExtractionRequest
    ) async throws -> [KnowledgeEntry] {
        request.text.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { entry(fromLine: String($0), for: request) }
    }

    private func entry(
        fromLine line: String, for request: KnowledgeExtractionRequest
    ) -> KnowledgeEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard let marked = Self.marked(in: trimmed) else { return nil }

        return KnowledgeEntry(
            id: KnowledgeEntryID.derived(
                fromSeed: "\(request.sourceContentHash.rawValue)/\(trimmed)"),
            projectID: request.projectID,
            kind: marked.kind,
            summaryText: marked.summaryText,
            source: request.source,
            sourceContentHash: request.sourceContentHash,
            createdAt: request.extractedAt
        )
    }

    private static func marked(
        in line: String
    ) -> (kind: KnowledgeEntryKind, summaryText: String)? {
        let uppercased = line.uppercased()

        for (marker, kind) in markers {
            guard let range = uppercased.range(of: marker) else { continue }

            let summaryText = String(line[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)

            guard !summaryText.isEmpty else { continue }

            return (kind, summaryText)
        }

        return nil
    }
}
