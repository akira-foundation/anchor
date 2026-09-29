import AnchorApplication
import AnchorDomain
import AnchorFoundation
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorKnowledge

@Suite("SQLite knowledge context reading")
struct SQLiteKnowledgeContextReadingTests {
    private let projectID = ProjectID.derived(fromSeed: "context-project")
    private let foreignProjectID = ProjectID.derived(fromSeed: "foreign-context-project")

    @Test("pages current project knowledge by timestamp and identifier without gaps")
    func pagesCurrentKnowledgeWithoutGaps() async throws {
        let (_, store, _) = try await seededStore()
        var cursor: ContextPageCursor?
        var visited: [KnowledgeEntry] = []
        let binding = makeBinding()

        repeat {
            let page = try await store.listCurrentKnowledge(
                forProject: projectID, kind: nil, origin: nil,
                page: pageRequest(limit: 2, cursor: cursor), binding: binding)
            #expect(page.records.count <= 2)
            visited += page.records
            cursor = page.nextCursor
            #expect((cursor != nil) == (visited.count < 7))
        } while cursor != nil

        #expect(
            visited.map(\.summaryText) == [
                "summary-classified", "decision-marked", "decision-classified",
                "todo-inferred", "risk", "architecture", "question",
            ])
        #expect(Set(visited.map(\.id)).count == visited.count)
    }

    @Test("kind and origin filters apply together")
    func combinesKindAndOriginFilters() async throws {
        let (_, store, entries) = try await seededStore()
        let decision = try #require(entries.first { $0.summaryText == "decision-marked" })
        let page = try await store.listCurrentKnowledge(
            forProject: projectID, kind: .decision, origin: .marked,
            page: pageRequest(limit: 10), binding: makeBinding())

        #expect(page.records.map(\.id) == [decision.id])
        #expect(page.nextCursor == nil)
    }

    @Test("detail reads the complete current authorized entry only")
    func loadsScopedCurrentDetail() async throws {
        let (_, store, entries) = try await seededStore()
        let supported = try #require(entries.first { $0.summaryText == "decision-marked" })
        let foreign = try #require(entries.first { $0.projectID == foreignProjectID })
        let superseded = try #require(entries.first { $0.state == .superseded })

        #expect(
            try await store.loadCurrentKnowledge(
                withIdentifier: supported.id, forProject: projectID) == supported)
        #expect(
            try await store.loadCurrentKnowledge(
                withIdentifier: foreign.id, forProject: projectID) == nil)
        #expect(
            try await store.loadCurrentKnowledge(
                withIdentifier: superseded.id, forProject: projectID) == nil)
        #expect(
            try await store.loadCurrentKnowledge(
                withIdentifier: KnowledgeEntryID(), forProject: projectID) == nil)
    }

    @Test(
        "malformed current rows fail both list and detail with typed store errors",
        arguments: ["source", "supporting_message_ids", "source_content_hash"])
    func malformedCurrentRowsFailStrictly(column: String) async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let malformed = entry(
            "malformed-\(column)", kind: .decision, origin: .marked, timestamp: 100)
        try await store.recordEntries(
            [malformed],
            supersedingEntriesFrom: .artifact(
                ArtifactID.derived(fromSeed: "unused-\(column)")))
        let expectedFailure: SQLiteKnowledgeStoreFailure
        switch column {
        case "source": expectedFailure = .invalidSource(malformed.id)
        case "supporting_message_ids":
            expectedFailure = .invalidSupportingMessageIdentifiers(malformed.id)
        default: expectedFailure = .malformedEntryRecord
        }
        try await database.run(
            "UPDATE knowledge_entries SET \(column) = ? WHERE id = ?;",
            [.text("not valid"), .text(malformed.id.rawValue)])

        await #expect(throws: expectedFailure) {
            try await store.listCurrentKnowledge(
                forProject: projectID, kind: nil, origin: nil,
                page: pageRequest(limit: 1), binding: makeBinding())
        }
        await #expect(throws: expectedFailure) {
            try await store.loadCurrentKnowledge(
                withIdentifier: malformed.id, forProject: projectID)
        }
    }

    private func seededStore() async throws -> (
        SQLiteDatabase, SQLiteKnowledgeStore, [KnowledgeEntry]
    ) {
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteKnowledgeStore(database: database)
        let tiedIDs = [
            KnowledgeEntryID(rawValue: "00000000-0000-0000-0000-000000000003")!,
            KnowledgeEntryID(rawValue: "00000000-0000-0000-0000-000000000001")!,
            KnowledgeEntryID(rawValue: "00000000-0000-0000-0000-000000000002")!,
        ]
        let messageIDs = [MessageID(), MessageID()]
        let entries = [
            entry("summary-classified", kind: .summary, origin: .classified, timestamp: 800),
            entry(
                "decision-marked", kind: .decision, origin: .marked, timestamp: 700,
                supportingMessageIDs: messageIDs),
            entry("decision-classified", kind: .decision, origin: .classified, timestamp: 650),
            entry(
                "todo-inferred", kind: .todo, origin: .inferred, timestamp: 600,
                supportingMessageIDs: messageIDs),
            entry("question", kind: .question, origin: .classified, timestamp: 500, id: tiedIDs[0]),
            entry("risk", kind: .risk, origin: .marked, timestamp: 500, id: tiedIDs[1]),
            entry(
                "architecture", kind: .architecture, origin: .classified, timestamp: 500,
                id: tiedIDs[2]),
            entry(
                "foreign", projectID: foreignProjectID, kind: .decision, origin: .marked,
                timestamp: 1000),
            entry("superseded", kind: .decision, origin: .marked, timestamp: 1200),
        ]
        try await store.recordEntries(
            entries,
            supersedingEntriesFrom: .artifact(
                ArtifactID.derived(fromSeed: "unused-supersession")))
        let superseded = entries[8]
        try await store.recordEntries([], supersedingEntriesFrom: superseded.source)
        let expectedEntries = entries.enumerated().map { index, candidate in
            index == 8
                ? entry(
                    "superseded", kind: .decision, origin: .marked,
                    timestamp: 1200, state: .superseded) : candidate
        }
        return (database, store, expectedEntries)
    }

    private func entry(
        _ seed: String, projectID: ProjectID? = nil, kind: KnowledgeEntryKind,
        origin: KnowledgeEntryOrigin, timestamp: TimeInterval,
        id: KnowledgeEntryID? = nil, state: KnowledgeEntryState = .current,
        supportingMessageIDs: [MessageID] = []
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: id ?? .derived(fromSeed: seed), projectID: projectID ?? self.projectID,
            kind: kind, summaryText: seed,
            source: .artifact(.derived(fromSeed: "source-\(seed)")),
            sourceContentHash: .digest(of: Data(seed.utf8)), origin: origin,
            supportingMessageIDs: supportingMessageIDs, state: state,
            createdAt: Date(timeIntervalSince1970: timestamp))
    }

    private func pageRequest(limit: Int, cursor: ContextPageCursor? = nil) -> ContextPageRequest {
        ContextPageRequest(limit: limit, cursor: cursor, maximumLimit: 100)!
    }

    private func makeBinding() -> ContextCursorBinding {
        ContextCursorBinding(
            workspaceURL: URL(fileURLWithPath: "/tmp/knowledge-workspace"),
            generation: ContextReadGeneration(identifier: UUID()))
    }
}
