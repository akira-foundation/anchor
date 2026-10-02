import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import AnchorSearch
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Persistent knowledge context")
struct PersistentKnowledgeContextTests {
    @Test("combined filters page current authorized knowledge one record at a time")
    func pagesFilteredCurrentKnowledge() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let seeded = try await seedKnowledge(writer: writer, projectID: fixture.observed.projectID)
        try await publish(writer.status)
        let reader = try await fixture.reader()
        var cursor: ContextPageCursor?
        var visited: [KnowledgeEntryID] = []

        repeat {
            let request = try #require(
                ListProjectKnowledgeRequest(
                    kind: .decision, origin: .marked, limit: 1, cursor: cursor))
            let page = try await reader.listKnowledge.perform(request)
            #expect(page.records.count == 1)
            visited += page.records.map(\.id)
            cursor = page.nextCursor
            #expect((cursor != nil) == (visited.count == 1))
        } while cursor != nil

        #expect(visited == [seeded.first.id, seeded.second.id])
        #expect(!visited.contains(seeded.superseded.id))
        #expect(!visited.contains(seeded.foreign.id))
    }

    @Test("a resume identifier opens complete knowledge with hash and evidence")
    func resumeIdentifierLoadsCompleteDetail() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let seeded = try await seedKnowledge(writer: writer, projectID: fixture.observed.projectID)
        try await publish(writer.status)
        let reader = try await fixture.reader()
        let resume = try await reader.resume.perform(ProjectContextRequest())
        let summary = try #require(resume.recentDecisions.first { $0.id == seeded.first.id })

        #expect(summary.summaryIsTruncated)
        let detail = try await reader.readKnowledge.perform(
            ReadProjectKnowledgeRequest(knowledgeEntryID: summary.id))
        #expect(detail == seeded.first)
        #expect(detail.summaryText.utf8.count > summary.summary.utf8.count)
        #expect(detail.sourceContentHash == seeded.first.sourceContentHash)
        #expect(detail.supportingMessageIDs == seeded.first.supportingMessageIDs)
    }

    @Test("superseded foreign and unknown identifiers stay hidden")
    func hiddenIdentifiersReturnEntityNotFound() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let seeded = try await seedKnowledge(writer: writer, projectID: fixture.observed.projectID)
        try await publish(writer.status)
        let reader = try await fixture.reader()

        for hiddenID in [
            seeded.superseded.id, seeded.foreign.id,
            KnowledgeEntryID.derived(fromSeed: "missing-persistent-knowledge"),
        ] {
            await #expect(throws: ContextQueryFailure.entityNotFound) {
                try await reader.readKnowledge.perform(
                    ReadProjectKnowledgeRequest(knowledgeEntryID: hiddenID))
            }
        }
    }

    @Test("an unavailable generation refuses both knowledge actions")
    func generationChangeReturnsContextUnavailable() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let seeded = try await seedKnowledge(writer: writer, projectID: fixture.observed.projectID)
        try await publish(writer.status)
        let reader = try await fixture.reader()
        let firstPage = try await reader.listKnowledge.perform(
            try #require(ListProjectKnowledgeRequest(limit: 1)))
        #expect(firstPage.records.count == 1)

        let update = try await writer.status.beginUpdate()
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.listKnowledge.perform(
                try #require(ListProjectKnowledgeRequest(limit: 1)))
        }
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.readKnowledge.perform(
                ReadProjectKnowledgeRequest(knowledgeEntryID: seeded.first.id))
        }
        try await writer.status.completeUpdate(update, succeeded: true)
    }

    @Test("a malformed selected row maps to a read failure for list and detail")
    func malformedSelectedRowReturnsReadFailed() async throws {
        let fixture = try ContextAssemblyFixture()
        defer { fixture.remove() }
        let writer = try await fixture.writer()
        let seeded = try await seedKnowledge(writer: writer, projectID: fixture.observed.projectID)
        try await publish(writer.status)
        try await writer.database.run(
            "UPDATE knowledge_entries SET source_content_hash = 'bad' WHERE id = ?;",
            [.text(seeded.first.id.rawValue)])
        let reader = try await fixture.reader()

        await #expect(throws: ContextQueryFailure.readFailed) {
            try await reader.listKnowledge.perform(
                try #require(
                    ListProjectKnowledgeRequest(kind: .decision, origin: .marked, limit: 1)))
        }
        await #expect(throws: ContextQueryFailure.readFailed) {
            try await reader.readKnowledge.perform(
                ReadProjectKnowledgeRequest(knowledgeEntryID: seeded.first.id))
        }
    }

    private func seedKnowledge(
        writer: ContextReadModelWriter, projectID: ProjectID
    ) async throws -> SeededKnowledge {
        _ = try await SQLiteContextSearch(database: writer.database)
        _ = try await SQLiteDevicePresenceSnapshotStore(database: writer.database)
        let knowledge = try await SQLiteKnowledgeStore(database: writer.database)
        let first = entry(
            "first-" + String(repeating: "x", count: 600), projectID: projectID,
            kind: .decision, origin: .marked, createdAt: 500,
            supportingMessageIDs: [MessageID.derived(fromSeed: "first-evidence")])
        let second = entry(
            "second", projectID: projectID, kind: .decision, origin: .marked,
            createdAt: 400)
        let otherOrigin = entry(
            "classified", projectID: projectID, kind: .decision, origin: .classified,
            createdAt: 600)
        let otherKind = entry(
            "todo", projectID: projectID, kind: .todo, origin: .marked,
            createdAt: 700)
        let foreign = entry(
            "foreign", projectID: ProjectID.derived(fromSeed: "foreign-knowledge-project"),
            kind: .decision, origin: .marked, createdAt: 800)
        let superseded = entry(
            "superseded", projectID: projectID, kind: .decision, origin: .marked,
            createdAt: 900)
        try await knowledge.recordEntries(
            [first, second, otherOrigin, otherKind, foreign, superseded],
            supersedingEntriesFrom: .artifact(ArtifactID.derived(fromSeed: "unused")))
        try await knowledge.recordEntries([], supersedingEntriesFrom: superseded.source)
        return SeededKnowledge(
            first: first, second: second, foreign: foreign, superseded: superseded)
    }

    private func entry(
        _ summary: String, projectID: ProjectID, kind: KnowledgeEntryKind,
        origin: KnowledgeEntryOrigin, createdAt: TimeInterval,
        supportingMessageIDs: [MessageID] = []
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: .derived(fromSeed: summary), projectID: projectID, kind: kind,
            summaryText: summary,
            source: .artifact(.derived(fromSeed: "source-\(summary)")),
            sourceContentHash: .digest(of: Data(summary.utf8)), origin: origin,
            supportingMessageIDs: supportingMessageIDs,
            createdAt: Date(timeIntervalSince1970: createdAt))
    }

    private func publish(_ status: ContextReadModelStatusStore) async throws {
        let update = try await status.beginUpdate(rebuilding: true)
        try await status.completeUpdate(update, succeeded: true)
    }
}

private struct SeededKnowledge {
    let first: KnowledgeEntry
    let second: KnowledgeEntry
    let foreign: KnowledgeEntry
    let superseded: KnowledgeEntry
}
