import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Testing

@testable import AnchorSearch

@Suite("Malformed persistent context")
struct SQLiteMalformedContextTests {
    @Test("malformed session metadata is an explicit failure")
    func malformedSessionFails() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let session = makeSession(identifierSuffix: 1, updatedAt: 20)
        try await search.indexTranscript(AgentTranscript(session: session, entries: []))
        try await database.run("UPDATE context_sessions SET provider = 'invalid';")
        await #expect(throws: (any Error).self) {
            try await search.loadSession(withIdentifier: session.id)
        }
        await #expect(throws: (any Error).self) {
            try await search.listSessions(
                forProject: session.projectID, provider: nil, page: makePageRequest(limit: 20))
        }
    }

    @Test(
        "malformed canonical entries are explicit failures",
        arguments: [
            "UPDATE context_entries SET role_or_tool = 'invalid';",
            "UPDATE context_entries SET entry_kind = 'unknown';",
        ])
    func malformedEntryFails(statement: String) async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let session = makeSession(identifierSuffix: 1, updatedAt: 20)
        try await search.indexTranscript(
            AgentTranscript(
                session: session,
                entries: [
                    makeMessage(sessionID: session.id, identifierSuffix: 1, text: "needle", at: 20)
                ]))
        try await database.run(statement)
        await #expect(throws: (any Error).self) {
            try await search.loadConversationEntries(
                inSession: session.id, page: makePageRequest(limit: 20))
        }
    }
}
