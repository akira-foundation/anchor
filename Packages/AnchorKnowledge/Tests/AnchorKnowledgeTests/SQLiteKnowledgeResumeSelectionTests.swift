import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import Foundation
import Testing

@Suite("SQLite knowledge resume selection")
struct SQLiteKnowledgeResumeSelectionTests {
    @Test("current entries are scoped ordered bounded and report additional rows")
    func currentEntriesFollowResumeSelectionRules() async throws {
        let projectID = ProjectID.derived(fromSeed: "knowledge-resume-project")
        let otherProjectID = ProjectID.derived(fromSeed: "other-knowledge-project")
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let tiedIDs = [
            KnowledgeEntryID.derived(fromSeed: "tie-z"),
            KnowledgeEntryID.derived(fromSeed: "tie-a"),
        ].sorted { $0.rawValue < $1.rawValue }
        let decisions = [
            entry("newest", projectID, .decision, 600),
            entry("tie-later-id", projectID, .decision, 500, id: tiedIDs[1]),
            entry("tie-first-id", projectID, .decision, 500, id: tiedIDs[0]),
            entry("fourth", projectID, .decision, 400),
            entry("fifth", projectID, .decision, 300),
            entry("sixth", projectID, .decision, 200),
        ]
        let todo = entry("latest-current-kind", projectID, .todo, 999)
        let foreign = entry("foreign", otherProjectID, .decision, 1_300)
        let supersededSource = KnowledgeEntrySource.artifact(
            ArtifactID.derived(fromSeed: "superseded-source"))
        let superseded = entry(
            "superseded-newer", projectID, .decision, 1_200, source: supersededSource)
        let replacement = entry(
            "replacement", projectID, .question, 100, source: supersededSource)

        try await store.recordEntries(
            decisions + [todo, foreign, superseded],
            supersedingEntriesFrom: .artifact(ArtifactID.derived(fromSeed: "unused-source")))
        try await store.recordEntries([replacement], supersedingEntriesFrom: supersededSource)

        let selection = try await store.loadCurrentEntries(
            forProject: projectID, kind: .decision, limit: 5)
        let expectedIDs = [
            decisions[0].id, tiedIDs[0], tiedIDs[1], decisions[3].id, decisions[4].id,
        ]

        #expect(selection.entries.map(\.id) == expectedIDs)
        #expect(selection.entries.allSatisfy { $0.projectID == projectID })
        #expect(selection.entries.allSatisfy { $0.kind == .decision && $0.state == .current })
        #expect(selection.hasMore)
        #expect(try await store.loadLatestCurrentEntryDate(forProject: projectID) == date(999))
        #expect(try await store.loadLatestCurrentEntryDate(forProject: ProjectID()) == nil)
    }

    @Test("malformed encoded sources fail rather than disappearing")
    func malformedSourceFailsStrictly() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let projectID = ProjectID.derived(fromSeed: "malformed-source-project")
        let malformed = entry("malformed-source", projectID, .decision, 10)
        try await store.recordEntries(
            [malformed],
            supersedingEntriesFrom: .artifact(ArtifactID.derived(fromSeed: "unused")))
        try await database.run(
            "UPDATE knowledge_entries SET source = 'not-json' WHERE id = ?;",
            [.text(malformed.id.rawValue)])

        await #expect(throws: (any Error).self) {
            try await store.loadCurrentEntries(forProject: projectID, kind: .decision, limit: 5)
        }
    }

    @Test("malformed supporting message identifiers fail rather than disappearing")
    func malformedSupportingMessageIdentifiersFailStrictly() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let projectID = ProjectID.derived(fromSeed: "malformed-support-project")
        let malformed = entry("malformed-support", projectID, .decision, 10)
        try await store.recordEntries(
            [malformed],
            supersedingEntriesFrom: .artifact(ArtifactID.derived(fromSeed: "unused")))
        try await database.run(
            "UPDATE knowledge_entries SET supporting_message_ids = '[\"bad\"]' WHERE id = ?;",
            [.text(malformed.id.rawValue)])

        await #expect(
            throws: SQLiteKnowledgeStoreFailure.invalidSupportingMessageIdentifiers(malformed.id)
        ) {
            try await store.loadCurrentEntries(forProject: projectID, kind: .decision, limit: 5)
        }
    }

    @Test("malformed required fields fail rather than producing a partial page")
    func malformedRequiredFieldsFailStrictly() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let projectID = ProjectID.derived(fromSeed: "malformed-required-project")
        let malformed = entry("malformed-required", projectID, .decision, 10)
        try await store.recordEntries(
            [malformed],
            supersedingEntriesFrom: .artifact(ArtifactID.derived(fromSeed: "unused")))
        try await database.run(
            "UPDATE knowledge_entries SET source_content_hash = 'bad' WHERE id = ?;",
            [.text(malformed.id.rawValue)])

        await #expect(throws: SQLiteKnowledgeStoreFailure.malformedEntryRecord) {
            try await store.loadCurrentEntries(forProject: projectID, kind: .decision, limit: 5)
        }
    }

    @Test("a malformed latest timestamp fails rather than appearing absent")
    func malformedLatestTimestampFailsStrictly() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let projectID = ProjectID.derived(fromSeed: "malformed-timestamp-project")
        let malformed = entry("malformed-timestamp", projectID, .decision, 10)
        try await store.recordEntries(
            [malformed],
            supersedingEntriesFrom: .artifact(ArtifactID.derived(fromSeed: "unused")))
        try await database.run(
            "UPDATE knowledge_entries SET created_at = 'bad' WHERE id = ?;",
            [.text(malformed.id.rawValue)])

        await #expect(throws: SQLiteKnowledgeStoreFailure.malformedEntryRecord) {
            try await store.loadLatestCurrentEntryDate(forProject: projectID)
        }
    }

    private func entry(
        _ seed: String, _ projectID: ProjectID, _ kind: KnowledgeEntryKind,
        _ createdAt: TimeInterval, id: KnowledgeEntryID? = nil,
        source: KnowledgeEntrySource? = nil
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: id ?? KnowledgeEntryID.derived(fromSeed: seed), projectID: projectID,
            kind: kind, summaryText: seed,
            source: source ?? .artifact(ArtifactID.derived(fromSeed: "\(seed)-source")),
            sourceContentHash: ContentHash.digest(of: Data(seed.utf8)), origin: .marked,
            createdAt: date(createdAt))
    }

    private func date(_ secondsSinceEpoch: TimeInterval) -> Date {
        Date(timeIntervalSince1970: secondsSinceEpoch)
    }
}
