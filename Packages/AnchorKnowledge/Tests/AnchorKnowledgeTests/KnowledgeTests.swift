import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorKnowledge

@Suite("Extracting what was explicitly marked")
struct MarkedKnowledgeExtractorTests {
    private let extractor = MarkedKnowledgeExtractor()
    private let projectID = ProjectID()
    private let artifactID = ArtifactID()

    private func request(
        _ text: String, digestOf source: String = "source"
    )
        -> KnowledgeExtractionRequest
    {
        KnowledgeExtractionRequest(
            text: text,
            projectID: projectID,
            source: .artifact(artifactID),
            sourceContentHash: ContentHash.digest(of: Data(source.utf8)),
            extractedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test(
        "each marker becomes the kind it names",
        arguments: [
            ("TODO: split the coordinator", KnowledgeEntryKind.todo),
            ("FIXME: the cursor never advances", .todo),
            ("Decision: SQLite backs the local index", .decision),
            ("Question: what happens when the key is lost", .question),
            ("Risk: the index can outgrow the disk", .risk),
            ("Architecture: storage is infrastructure", .architecture),
            ("Summary: nineteen phases are done", .summary),
        ]
    )
    func eachMarkerBecomesTheKindItNames(line: String, kind: KnowledgeEntryKind) async throws {
        let entries = try await extractor.extractEntries(for: request(line))

        #expect(entries.count == 1)
        #expect(entries.first?.kind == kind)
    }

    @Test("the text after the marker is what is kept")
    func theTextAfterTheMarkerIsWhatIsKept() async throws {
        let entries = try await extractor.extractEntries(
            for: request("  TODO: split the coordinator  "))

        #expect(entries.first?.summaryText == "split the coordinator")
    }

    @Test("a line with no marker produces nothing")
    func aLineWithNoMarkerProducesNothing() async throws {
        let entries = try await extractor.extractEntries(
            for: request("we talked about splitting the coordinator"))

        #expect(entries.isEmpty)
    }

    @Test("a marker with nothing after it produces nothing")
    func aMarkerWithNothingAfterItProducesNothing() async throws {
        #expect(try await extractor.extractEntries(for: request("TODO:")).isEmpty)
    }

    @Test("every entry carries the source it came from")
    func everyEntryCarriesTheSourceItCameFrom() async throws {
        let entries = try await extractor.extractEntries(for: request("TODO: wire the app"))

        #expect(entries.first?.source == .artifact(artifactID))
        #expect(entries.first?.projectID == projectID)
    }

    @Test("the same line in the same source keeps the same identity")
    func theSameLineInTheSameSourceKeepsTheSameIdentity() async throws {
        let first = try await extractor.extractEntries(for: request("TODO: wire the app"))
        let second = try await extractor.extractEntries(for: request("TODO: wire the app"))

        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test("the same line in a changed source is a different entry")
    func theSameLineInAChangedSourceIsADifferentEntry() async throws {
        let first = try await extractor.extractEntries(
            for: request("TODO: wire the app", digestOf: "before"))
        let second = try await extractor.extractEntries(
            for: request("TODO: wire the app", digestOf: "after"))

        #expect(first.map(\.id) != second.map(\.id))
    }
}

@Suite("Keeping knowledge and its source together")
struct SQLiteKnowledgeStoreTests {
    private let projectID = ProjectID()
    private let artifactID = ArtifactID()

    private func makeStore() async throws -> SQLiteKnowledgeStore {
        try await SQLiteKnowledgeStore(database: try SQLiteDatabase(fileURL: nil))
    }

    private func entry(_ text: String, digestOf source: String) -> KnowledgeEntry {
        KnowledgeEntry(
            id: KnowledgeEntryID(),
            projectID: projectID,
            kind: .decision,
            summaryText: text,
            source: .artifact(artifactID),
            sourceContentHash: ContentHash.digest(of: Data(source.utf8)),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("what was recorded comes back for its project")
    func whatWasRecordedComesBackForItsProject() async throws {
        let store = try await makeStore()

        try await store.recordEntries(
            [entry("SQLite backs the index", digestOf: "one")],
            supersedingEntriesFrom: .artifact(artifactID)
        )

        let found = try await store.entries(forProject: projectID, includingSuperseded: false)

        #expect(found.map(\.summaryText) == ["SQLite backs the index"])
    }

    @Test("a source that moved on supersedes what it had said")
    func aSourceThatMovedOnSupersedesWhatItHadSaid() async throws {
        let store = try await makeStore()

        try await store.recordEntries(
            [entry("SQLite backs the index", digestOf: "one")],
            supersedingEntriesFrom: .artifact(artifactID)
        )
        try await store.recordEntries(
            [entry("Postgres backs the index", digestOf: "two")],
            supersedingEntriesFrom: .artifact(artifactID)
        )

        let current = try await store.entries(forProject: projectID, includingSuperseded: false)
        let all = try await store.entries(forProject: projectID, includingSuperseded: true)

        #expect(current.map(\.summaryText) == ["Postgres backs the index"])
        #expect(all.count == 2)
        #expect(all.filter { $0.state == .superseded }.count == 1)
    }

    @Test("superseding one source leaves another alone")
    func supersedingOneSourceLeavesAnotherAlone() async throws {
        let store = try await makeStore()
        let otherArtifactID = ArtifactID()
        let fromElsewhere = KnowledgeEntry(
            id: KnowledgeEntryID(), projectID: projectID, kind: .risk,
            summaryText: "the index can outgrow the disk",
            source: .artifact(otherArtifactID),
            sourceContentHash: ContentHash.digest(of: Data("elsewhere".utf8)),
            createdAt: Date(timeIntervalSince1970: 0)
        )

        try await store.recordEntries(
            [fromElsewhere], supersedingEntriesFrom: .artifact(otherArtifactID))
        try await store.recordEntries(
            [entry("SQLite backs the index", digestOf: "one")],
            supersedingEntriesFrom: .artifact(artifactID)
        )

        let current = try await store.entries(forProject: projectID, includingSuperseded: false)

        #expect(current.count == 2)
    }

    @Test("another project's knowledge is not returned")
    func anotherProjectsKnowledgeIsNotReturned() async throws {
        let store = try await makeStore()

        try await store.recordEntries(
            [entry("SQLite backs the index", digestOf: "one")],
            supersedingEntriesFrom: .artifact(artifactID)
        )

        #expect(
            try await store.entries(forProject: ProjectID(), includingSuperseded: true).isEmpty)
    }

    @Test("a summary carrying quotes cannot change the statement")
    func aSummaryCarryingQuotesCannotChangeTheStatement() async throws {
        let store = try await makeStore()

        try await store.recordEntries(
            [entry("'; DROP TABLE knowledge_entries; --", digestOf: "one")],
            supersedingEntriesFrom: .artifact(artifactID)
        )

        let found = try await store.entries(forProject: projectID, includingSuperseded: false)

        #expect(found.map(\.summaryText) == ["'; DROP TABLE knowledge_entries; --"])
    }
}
