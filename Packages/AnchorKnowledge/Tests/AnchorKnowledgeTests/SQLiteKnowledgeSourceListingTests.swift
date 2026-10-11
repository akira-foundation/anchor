import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import Foundation
import Testing

@Suite("SQLite knowledge source listing")
struct SQLiteKnowledgeSourceListingTests {
    private let projectID = ProjectID()

    @Test("lists each source of the project once, superseded ones included")
    func listsDistinctSourcesIncludingSuperseded() async throws {
        let store = try await SQLiteKnowledgeStore(database: try SQLiteDatabase(fileURL: nil))
        let retired = KnowledgeEntrySource.artifact(ArtifactID())
        let active = KnowledgeEntrySource.session(SessionID())
        try await store.recordEntries(
            [entry("old plan", retired, 10)], supersedingEntriesFrom: retired)
        try await store.recordEntries([], supersedingEntriesFrom: retired)
        try await store.recordEntries(
            [entry("first", active, 20), entry("second", active, 30)],
            supersedingEntriesFrom: active)

        let listing = try await store.loadPublishableKnowledge(forProject: projectID)

        #expect(listing.sources == [retired, active])
        #expect(listing.currentEntries.map(\.summaryText) == ["first", "second"])
    }

    @Test("sources and entries of another project are not listed")
    func sourcesOfAnotherProjectAreNotListed() async throws {
        let store = try await SQLiteKnowledgeStore(database: try SQLiteDatabase(fileURL: nil))
        let foreignSource = KnowledgeEntrySource.session(SessionID())
        try await store.recordEntries(
            [entry("foreign", foreignSource, 10, projectID: ProjectID())],
            supersedingEntriesFrom: foreignSource)

        let listing = try await store.loadPublishableKnowledge(forProject: projectID)

        #expect(listing.sources.isEmpty)
        #expect(listing.currentEntries.isEmpty)
    }

    private func entry(
        _ summary: String, _ source: KnowledgeEntrySource, _ createdAt: TimeInterval,
        projectID entryProjectID: ProjectID? = nil
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: KnowledgeEntryID(), projectID: entryProjectID ?? projectID, kind: .decision,
            summaryText: summary, source: source,
            sourceContentHash: .digest(of: Data(summary.utf8)),
            createdAt: Date(timeIntervalSince1970: createdAt))
    }
}
