import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorSearch

@Suite("Authorized conversation reads and counts")
struct SQLiteProjectConversationTests {
    @Test("session counts persist exactly across reopening")
    func sessionCountsSurviveReopening() async throws {
        let fileURL = makeDatabaseFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let session = makeSession(identifierSuffix: 700, updatedAt: 30)
        let search = try await SQLiteContextSearch(database: SQLiteDatabase(fileURL: fileURL))
        try await search.indexTranscript(
            AgentTranscript(
                session: session,
                entries: [
                    makeMessage(sessionID: session.id, identifierSuffix: 701, text: "one", at: 10),
                    makeMessage(sessionID: session.id, identifierSuffix: 702, text: "two", at: 20),
                    makeActivity(sessionID: session.id, identifierSuffix: 703, at: 30),
                ]))
        let reopened = SQLiteContextSearch(
            existingDatabase: try SQLiteDatabase(fileURL: fileURL, readOnly: true))
        let details = try #require(try await reopened.loadSession(withIdentifier: session.id))
        #expect(details.messageCount == 2)
        #expect(details.toolActivityCount == 1)
        let listed = try await reopened.listSessions(
            forProject: session.projectID, provider: nil, page: makePageRequest(limit: 20))
        #expect(listed.records == [details])
    }

    @Test("a first conversation page refuses another project's session")
    func foreignProjectConversationIsRefused() async throws {
        let search = try await SQLiteContextSearch(database: SQLiteDatabase(fileURL: nil))
        let session = makeSession(identifierSuffix: 800, projectIdentifierSuffix: 6, updatedAt: 20)
        try await search.indexTranscript(
            AgentTranscript(
                session: session,
                entries: [
                    makeMessage(
                        sessionID: session.id, identifierSuffix: 801, text: "private", at: 20)
                ]))
        await #expect(throws: ContextQueryFailure.entityNotFound) {
            try await search.loadConversationEntries(
                inSession: session.id, forProject: projectID(7), page: makePageRequest(limit: 20))
        }
    }

    @Test("project authorization and entries remain in one snapshot at reassignment")
    func authorizedConversationUsesOneSnapshot() async throws {
        let fileURL = makeDatabaseFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let session = makeSession(identifierSuffix: 900, projectIdentifierSuffix: 6, updatedAt: 20)
        let entry = makeMessage(
            sessionID: session.id, identifierSuffix: 901, text: "authorized", at: 20)
        let writer = try await SQLiteContextSearch(database: SQLiteDatabase(fileURL: fileURL))
        try await writer.indexTranscript(AgentTranscript(session: session, entries: [entry]))
        let reassignment = SQLiteOwnershipReadReassignment(
            databaseFileURL: fileURL,
            statements: """
                BEGIN IMMEDIATE;
                UPDATE context_sessions SET project_id = '\(projectID(7).rawValue)';
                UPDATE context_entries SET body = 'private reassigned content';
                COMMIT;
                """)
        let reader = try await SQLiteContextSearch(
            database: SQLiteDatabase(fileURL: fileURL, statementObserver: reassignment))
        let page = try await reader.loadConversationEntries(
            inSession: session.id,
            forProject: session.projectID, page: makePageRequest(limit: 20))
        try await reassignment.verifyWriteAttempt()
        #expect(page.records == [entry])
        let reassigned = makeSession(
            identifierSuffix: 900, projectIdentifierSuffix: 7, updatedAt: 30)
        try await writer.indexTranscript(AgentTranscript(session: reassigned, entries: [entry]))
        await #expect(throws: ContextQueryFailure.entityNotFound) {
            try await reader.loadConversationEntries(
                inSession: session.id, forProject: session.projectID,
                page: makePageRequest(limit: 20))
        }
    }
}
