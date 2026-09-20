import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorSearch

@Suite("Project-scoped search and replacement")
struct SQLiteProjectContextSearchTests {
    @Test("search pages bind project and query and break timestamp ties by entry identity")
    func searchPagesBindProjectAndQuery() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let session = makeSession(identifierSuffix: 1, updatedAt: 20)
        let other = makeSession(identifierSuffix: 2, projectIdentifierSuffix: 8, updatedAt: 30)
        try await search.indexTranscript(
            AgentTranscript(
                session: session,
                entries: [
                    makeMessage(
                        sessionID: session.id, identifierSuffix: 2, text: "needle second", at: 20),
                    makeMessage(
                        sessionID: session.id, identifierSuffix: 1, text: "needle first", at: 20),
                    makeActivity(
                        sessionID: session.id, identifierSuffix: 3, invocation: "needle tool",
                        at: 10),
                ]))
        try await search.indexTranscript(
            AgentTranscript(
                session: other,
                entries: [
                    makeMessage(
                        sessionID: other.id, identifierSuffix: 4, text: "needle secret", at: 30)
                ]))
        let first = try await search.searchContext(
            forProject: session.projectID, matching: "needle", page: makePageRequest(limit: 1))
        #expect(first.records.map(\.excerpt) == ["needle first"])
        let cursor = try #require(first.nextCursor)
        let second = try await search.searchContext(
            forProject: session.projectID, matching: "needle",
            page: makePageRequest(limit: 2, cursor: cursor))
        #expect(second.records.map(\.excerpt) == ["needle second", "needle tool\npassed"])
        #expect(second.nextCursor == nil)
        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.searchContext(
                forProject: other.projectID, matching: "needle",
                page: makePageRequest(limit: 1, cursor: cursor))
        }
        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.searchContext(
                forProject: session.projectID, matching: "other",
                page: makePageRequest(limit: 1, cursor: cursor))
        }
        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.listSessions(
                forProject: session.projectID, provider: nil,
                page: makePageRequest(limit: 1, cursor: cursor))
        }
    }

    @Test(
        "replacing a project removes stale sessions entries and FTS while preserving other projects"
    )
    func replacementRemovesStaleRows() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let stale = makeSession(identifierSuffix: 1, updatedAt: 10)
        let kept = makeSession(identifierSuffix: 2, projectIdentifierSuffix: 8, updatedAt: 20)
        for session in [stale, kept] {
            try await search.indexTranscript(
                AgentTranscript(
                    session: session,
                    entries: [
                        makeMessage(
                            sessionID: session.id, identifierSuffix: session == stale ? 1 : 2,
                            text: "needle", at: 10)
                    ]))
        }
        try await search.replaceTranscripts([], forProject: stale.projectID)
        try await search.replaceTranscripts([], forProject: stale.projectID)
        #expect(try await search.loadSession(withIdentifier: stale.id) == nil)
        #expect(
            try await search.loadConversationEntries(
                inSession: stale.id, page: makePageRequest(limit: 20)
            ).records.isEmpty)
        #expect(
            try await search.findContext(matching: "needle", limit: 20).map(\.sessionID) == [
                kept.id
            ])
        await #expect(throws: ContextReplacementFailure.projectMismatch) {
            try await search.replaceTranscripts(
                [AgentTranscript(session: kept, entries: [])], forProject: stale.projectID)
        }
        #expect(try await search.loadSession(withIdentifier: kept.id)?.session == kept)
    }
}
