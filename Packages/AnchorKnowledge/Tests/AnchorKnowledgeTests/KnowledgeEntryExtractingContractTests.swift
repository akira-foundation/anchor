import Foundation
import Testing

@testable import AnchorKnowledge

private struct LineSplittingKnowledgeEntryExtractor: KnowledgeEntryExtracting {
    func extractKnowledgeEntrySummaries(fromSourceText sourceText: String) async throws -> [String] {
        sourceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

@Suite("KnowledgeEntryExtracting contract")
struct KnowledgeEntryExtractingContractTests {
    @Test("source text yields one summary per non-empty line")
    func sourceTextYieldsOneSummaryPerNonEmptyLine() async throws {
        let knowledgeEntryExtractor = LineSplittingKnowledgeEntryExtractor()

        let extractedSummaries = try await knowledgeEntryExtractor
            .extractKnowledgeEntrySummaries(fromSourceText: "decided on SQLite\n\n  deferred iCloud  ")

        #expect(extractedSummaries == ["decided on SQLite", "deferred iCloud"])
    }

    @Test("empty source text yields no summaries")
    func emptySourceTextYieldsNoSummaries() async throws {
        let knowledgeEntryExtractor = LineSplittingKnowledgeEntryExtractor()

        #expect(try await knowledgeEntryExtractor.extractKnowledgeEntrySummaries(fromSourceText: "").isEmpty)
    }
}
