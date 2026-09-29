import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Knowledge context actions")
struct KnowledgeContextActionTests {
    @Test("knowledge listing defaults to fifty and permits one hundred")
    func knowledgeListRequestUsesBoundedDefaults() {
        #expect(ListProjectKnowledgeRequest()?.page.limit == 50)
        #expect(ListProjectKnowledgeRequest(limit: 100)?.page.limit == 100)
    }

    @Test("knowledge listing rejects out of range limits")
    func knowledgeListRequestRejectsOutOfRangeLimits() {
        #expect(ListProjectKnowledgeRequest(limit: 0) == nil)
        #expect(ListProjectKnowledgeRequest(limit: 101) == nil)
    }

    @Test("knowledge summaries preserve UTF8 scalar boundaries")
    func knowledgeSummaryPreservesUTF8Boundaries() throws {
        let fixture = try ContextQueryFixture()
        let summaries = [
            String(repeating: "a", count: 512),
            String(repeating: "a", count: 513),
            String(repeating: "𠀀", count: 128),
            "a" + String(repeating: "𠀀", count: 128),
        ]
        let compacted = summaries.map { summary in
            KnowledgeContextSummary(
                compacting: knowledgeEntry(summary, fixture: fixture),
                maximumSummaryByteCount: 512)
        }
        let exactASCII = compacted[0]
        let overlongASCII = compacted[1]
        let exactScalars = compacted[2]
        let overlongScalars = compacted[3]

        #expect(exactASCII.summary.utf8.count == 512)
        #expect(!exactASCII.summaryIsTruncated)
        #expect(overlongASCII.summary.utf8.count <= 512)
        #expect(overlongASCII.summary.hasSuffix("… [truncated]"))
        #expect(overlongASCII.summaryIsTruncated)
        #expect(exactScalars.summary.utf8.count == 512)
        #expect(!exactScalars.summaryIsTruncated)
        #expect(overlongScalars.summary.utf8.count <= 512)
        #expect(overlongScalars.summary.hasSuffix("… [truncated]"))
        #expect(overlongScalars.summaryIsTruncated)
    }

    @Test("knowledge listing authorizes and forwards filters and binding")
    func listKnowledgeAuthorizesAndForwardsFiltersAndBinding() async throws {
        let fixture = try ContextQueryFixture()
        let entry = knowledgeEntry(String(repeating: "a", count: 513), fixture: fixture)
        let cursor = try #require(ContextPageCursor(rawValue: "next-page"))
        let reader = KnowledgeContextReaderSpy(entry: entry, nextCursor: cursor)
        let request = try #require(
            ListProjectKnowledgeRequest(
                kind: .decision, origin: .inferred, limit: 2))

        let page = try await ListProjectKnowledgeAction(
            workspace: fixture, knowledge: reader, availability: fixture
        ).perform(request)

        let calls = await reader.listCalls
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.projectID == fixture.project.projectID)
        #expect(call.kind == .decision)
        #expect(call.origin == .inferred)
        #expect(call.page.limit == 2)
        #expect(call.binding.workspacePath == "/query")
        #expect(call.binding.generation == fixture.generation)
        #expect(page.nextCursor == cursor)
        #expect(page.records.count == 1)
        #expect(page.records[0].id == entry.id)
        #expect(page.records[0].summary.utf8.count <= 512)
        #expect(page.records[0].summaryIsTruncated)
    }

    @Test("knowledge detail scopes its identifier to the authorized project")
    func readKnowledgeScopesTheIdentifierToTheAuthorizedProject() async throws {
        let fixture = try ContextQueryFixture()
        let entry = knowledgeEntry("Complete record", fixture: fixture)
        let reader = KnowledgeContextReaderSpy(entry: entry)

        let loaded = try await ReadProjectKnowledgeAction(
            workspace: fixture, knowledge: reader, availability: fixture
        ).perform(ReadProjectKnowledgeRequest(knowledgeEntryID: entry.id))

        #expect(await reader.detailIdentifiers == [entry.id])
        #expect(await reader.detailProjects == [fixture.project.projectID])
        #expect(loaded == entry)
    }

    @Test("knowledge detail hides missing entries")
    func readKnowledgeHidesMissingEntries() async throws {
        let fixture = try ContextQueryFixture()
        let entry = knowledgeEntry("Complete record", fixture: fixture)
        let reader = KnowledgeContextReaderSpy(entry: entry, hasEntry: false)

        await #expect(throws: ContextQueryFailure.entityNotFound) {
            try await ReadProjectKnowledgeAction(
                workspace: fixture, knowledge: reader, availability: fixture
            ).perform(ReadProjectKnowledgeRequest(knowledgeEntryID: entry.id))
        }
    }

    @Test("knowledge detail hides entries returned from another project")
    func readKnowledgeHidesCrossProjectEntries() async throws {
        let fixture = try ContextQueryFixture()
        let foreignEntry = KnowledgeEntry(
            id: KnowledgeEntryID(),
            projectID: ProjectID.derived(fromSeed: "foreign-query-project"),
            kind: .decision,
            summaryText: "Foreign decision",
            source: .session(fixture.session.id),
            sourceContentHash: ContentHash.digest(of: Data("Foreign decision".utf8)),
            createdAt: .distantPast)

        await #expect(throws: ContextQueryFailure.entityNotFound) {
            try await ReadProjectKnowledgeAction(
                workspace: fixture,
                knowledge: CrossProjectKnowledgeReader(entry: foreignEntry),
                availability: fixture
            ).perform(ReadProjectKnowledgeRequest(knowledgeEntryID: foreignEntry.id))
        }
    }

    @Test("knowledge actions map cursor and driver errors and preserve availability errors")
    func knowledgeActionsMapCursorAndDriverFailures() async throws {
        let fixture = try ContextQueryFixture()
        let entry = knowledgeEntry("Complete record", fixture: fixture)
        for (failure, expected) in [
            (KnowledgeContextReaderSpy.Failure.cursor, ContextQueryFailure.invalidCursor),
            (.storage, .readFailed), (.unavailable, .contextUnavailable),
        ] {
            let reader = KnowledgeContextReaderSpy(entry: entry, failure: failure)
            await #expect(throws: expected) {
                try await ListProjectKnowledgeAction(
                    workspace: fixture, knowledge: reader, availability: fixture
                ).perform(try #require(ListProjectKnowledgeRequest()))
            }
            await #expect(throws: expected) {
                try await ReadProjectKnowledgeAction(
                    workspace: fixture, knowledge: reader, availability: fixture
                ).perform(ReadProjectKnowledgeRequest(knowledgeEntryID: entry.id))
            }
        }
    }
}

private func knowledgeEntry(_ summary: String, fixture: ContextQueryFixture) -> KnowledgeEntry {
    KnowledgeEntry(
        id: KnowledgeEntryID(), projectID: fixture.project.projectID, kind: .decision,
        summaryText: summary, source: .session(fixture.session.id),
        sourceContentHash: ContentHash.digest(of: Data(summary.utf8)), createdAt: .distantPast)
}

private struct CrossProjectKnowledgeReader: KnowledgeContextReading {
    let entry: KnowledgeEntry

    func listCurrentKnowledge(
        forProject projectID: ProjectID, kind: KnowledgeEntryKind?, origin: KnowledgeEntryOrigin?,
        page: ContextPageRequest, binding: ContextCursorBinding
    ) async throws -> ContextPage<KnowledgeEntry> {
        ContextPage(records: [], nextCursor: nil)
    }

    func loadCurrentKnowledge(
        withIdentifier knowledgeEntryID: KnowledgeEntryID, forProject projectID: ProjectID
    ) async throws -> KnowledgeEntry? {
        entry
    }
}
