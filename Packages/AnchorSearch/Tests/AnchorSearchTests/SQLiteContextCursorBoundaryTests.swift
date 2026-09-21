import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorSearch

@Suite("Bound SQLite context cursors")
struct SQLiteContextCursorBoundaryTests {
    @Test("all SQLite page cursors reject sibling workspaces and expired generations")
    func cursorWorkspaceAndGenerationMustMatch() throws {
        for operation in [
            SQLiteContextCursorOperation.searchProject, .listSessions,
            .loadConversationEntries,
        ] {
            let cursor = try SQLiteContextCursor.encode(
                operation: operation, scopeBinding: projectID().rawValue,
                filterBinding: "", binding: contextCursorTestBinding,
                position: SQLiteContextCursorPosition(timestamp: 10, identifier: "entry"))
            for mismatchedBinding in [
                siblingWorkspaceCursorBinding,
                expiredGenerationCursorBinding,
            ] {
                #expect(throws: ContextCursorFailure.invalid) {
                    try SQLiteContextCursor.decode(
                        cursor, operation: operation, scopeBinding: projectID().rawValue,
                        filterBinding: "", binding: mismatchedBinding)
                }
            }
        }
    }

    @Test("a session cursor cannot be used for conversation entries")
    func cursorOperationMustMatch() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let firstSession = makeSession(identifierSuffix: 101, updatedAt: 300)
        let secondSession = makeSession(identifierSuffix: 102, updatedAt: 200)
        try await search.indexTranscript(
            AgentTranscript(
                session: firstSession,
                entries: [
                    makeMessage(
                        sessionID: firstSession.id, identifierSuffix: 103,
                        text: "conversation", at: 100)
                ]))
        try await search.indexTranscript(AgentTranscript(session: secondSession, entries: []))
        let sessionPage = try await search.listSessions(
            forProject: firstSession.projectID, provider: nil, page: makePageRequest(limit: 1))

        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.loadConversationEntries(
                inSession: firstSession.id,
                page: makePageRequest(limit: 1, cursor: sessionPage.nextCursor))
        }
    }

    @Test("a session cursor cannot cross projects")
    func sessionCursorProjectMustMatch() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let firstSession = makeSession(
            identifierSuffix: 111, projectIdentifierSuffix: 7, updatedAt: 300)
        let secondSession = makeSession(
            identifierSuffix: 112, projectIdentifierSuffix: 7, updatedAt: 200)
        for session in [firstSession, secondSession] {
            try await search.indexTranscript(AgentTranscript(session: session, entries: []))
        }
        let firstPage = try await search.listSessions(
            forProject: projectID(7), provider: nil, page: makePageRequest(limit: 1))

        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.listSessions(
                forProject: projectID(8), provider: nil,
                page: makePageRequest(limit: 1, cursor: firstPage.nextCursor))
        }
    }

    @Test("a session cursor cannot cross provider filters")
    func sessionCursorProviderFilterMustMatch() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let firstSession = makeSession(identifierSuffix: 121, updatedAt: 300)
        let secondSession = makeSession(identifierSuffix: 122, updatedAt: 200)
        for session in [firstSession, secondSession] {
            try await search.indexTranscript(AgentTranscript(session: session, entries: []))
        }
        let firstPage = try await search.listSessions(
            forProject: projectID(), provider: nil, page: makePageRequest(limit: 1))

        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.listSessions(
                forProject: projectID(), provider: .claude,
                page: makePageRequest(limit: 1, cursor: firstPage.nextCursor))
        }
    }

    @Test("fractional session timestamps outrank opposing identifiers across pages")
    func fractionalSessionTimestampsDeterminePaginationOrder() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let newerLargerIdentifier = makeSession(identifierSuffix: 139, updatedAt: 100.9)
        let olderSmallerIdentifier = makeSession(identifierSuffix: 130, updatedAt: 100.1)
        try await search.indexTranscript(
            AgentTranscript(session: olderSmallerIdentifier, entries: []))
        try await search.indexTranscript(
            AgentTranscript(session: newerLargerIdentifier, entries: []))

        let firstPage = try await search.listSessions(
            forProject: projectID(), provider: nil, page: makePageRequest(limit: 1))
        let secondPage = try await search.listSessions(
            forProject: projectID(), provider: nil,
            page: makePageRequest(limit: 1, cursor: firstPage.nextCursor))

        #expect(firstPage.records.map(\.session) == [newerLargerIdentifier])
        #expect(secondPage.records.map(\.session) == [olderSmallerIdentifier])
    }

    @Test("unsupported cursor versions and malformed tokens are invalid")
    func cursorVersionAndEncodingMustBeValid() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let unsupportedVersionCursor = makeCursor(
            rawJSON: """
                {"version":1,"operation":"list-sessions","scopeBinding":"\(projectID().rawValue)","filterBinding":"","lastSortTimestamp":100000000,"lastIdentifier":"\(sessionID(131).rawValue)"}
                """)
        let malformedCursor = ContextPageCursor(rawValue: "not-a-json-token")!

        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.listSessions(
                forProject: projectID(), provider: nil,
                page: makePageRequest(limit: 1, cursor: unsupportedVersionCursor))
        }
        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.listSessions(
                forProject: projectID(), provider: nil,
                page: makePageRequest(limit: 1, cursor: malformedCursor))
        }
    }
}
