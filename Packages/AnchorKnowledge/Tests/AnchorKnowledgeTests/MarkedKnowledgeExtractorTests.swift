import AnchorDomain
import Foundation
import Testing

@testable import AnchorKnowledge

@Suite("A marker marks a line, it does not merely appear in one")
struct MarkerPositionTests {
    private let projectID = ProjectID()

    private func request(_ text: String) -> KnowledgeExtractionRequest {
        KnowledgeExtractionRequest(
            text: text,
            projectID: projectID,
            source: .session(SessionID()),
            sourceContentHash: ContentHash.digest(of: Data(text.utf8)),
            extractedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    @Test("a line that opens with a marker is marked")
    func lineThatOpensWithMarkerIsMarked() async throws {
        let entries = try await MarkedKnowledgeExtractor()
            .extractEntries(for: request("DECISION: keep the journal local"))

        #expect(entries.map(\.summaryText) == ["keep the journal local"])
    }

    @Test(
        "a marker behind ordinary list punctuation still marks the line",
        arguments: ["- TODO: wire it", "* TODO: wire it", "> TODO: wire it", "  1. TODO: wire it"]
    )
    func markerBehindOrdinaryListPunctuationStillMarksLine(line: String) async throws {
        let entries = try await MarkedKnowledgeExtractor().extractEntries(for: request(line))

        #expect(entries.map(\.summaryText) == ["wire it"])
    }

    @Test(
        "a line that merely talks about a marker is not marked",
        arguments: [
            "the markers are `TODO:`, `FIXME:` and the rest",
            "after removing it we get `decision, todo, decision`",
            "I asked whether TODO: counts here",
            "see the SUMMARY: section below for context",
        ]
    )
    func lineThatMerelyTalksAboutMarkerIsNotMarked(line: String) async throws {
        let entries = try await MarkedKnowledgeExtractor().extractEntries(for: request(line))

        #expect(entries.isEmpty)
    }

    @Test("what the line says after the marker is kept whole")
    func whatLineSaysAfterMarkerIsKeptWhole() async throws {
        let entries = try await MarkedKnowledgeExtractor()
            .extractEntries(for: request("- TODO: retry the upload after 3 attempts."))

        #expect(entries.map(\.summaryText) == ["retry the upload after 3 attempts."])
    }

    @Test("a marker with nothing after it marks nothing")
    func markerWithNothingAfterItMarksNothing() async throws {
        let entries = try await MarkedKnowledgeExtractor()
            .extractEntries(for: request("Summary:\nTODO:   "))

        #expect(entries.isEmpty)
    }
}
