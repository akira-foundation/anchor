import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorSearch

@Suite("Search candidate integrity")
struct SQLiteSearchIntegrityTests {
    @Test(
        "search actions expose corrupt or orphaned candidates as read failures",
        arguments: [
            "UPDATE context_entries SET entry_kind = 'unknown';",
            "UPDATE context_entries SET role_or_tool = 'invalid';",
            "UPDATE context_entries SET body = 'unrelated';",
            "UPDATE context_entries SET entry_id = 'invalid';",
            "UPDATE context_entries SET recorded_at = 1;",
            "UPDATE message_text SET provider = 'invalid';",
            "DELETE FROM context_entries;",
            "DELETE FROM context_sessions;",
        ])
    func searchActionRejectsCorruptCandidates(statement: String) async throws {
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
        let workspace = SearchIntegrityWorkspace(projectID: session.projectID)
        let action = SearchProjectContextAction(
            workspace: workspace, search: search, availability: workspace)
        await #expect(throws: ContextQueryFailure.readFailed) {
            try await action.perform(try #require(SearchProjectContextRequest(text: "needle")))
        }
    }

    @Test("one intact duplicate cannot hide another corrupt candidate")
    func duplicateCandidateCannotHideCorruption() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let session = makeSession(identifierSuffix: 1, updatedAt: 20)
        try await search.indexTranscript(
            AgentTranscript(
                session: session,
                entries: [
                    makeMessage(sessionID: session.id, identifierSuffix: 1, text: "needle", at: 20),
                    makeMessage(sessionID: session.id, identifierSuffix: 2, text: "needle", at: 20),
                ]))
        let healthy = try await search.searchContext(
            forProject: session.projectID, matching: "needle", page: makePageRequest(limit: 20))
        #expect(healthy.records.count == 2)
        try await database.run(
            "UPDATE context_entries SET entry_kind = 'unknown' WHERE entry_id = ?;",
            [.text(messageID(1).rawValue)])
        await #expect(throws: SQLiteContextReadFailure.malformedEntry) {
            try await search.searchContext(
                forProject: session.projectID, matching: "needle", page: makePageRequest(limit: 20))
        }
    }

    @Test("search validation and pagination share one snapshot across a concurrent corruption")
    func validationAndPaginationShareSnapshot() async throws {
        let fileURL = makeDatabaseFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let writer = try await SQLiteContextSearch(database: SQLiteDatabase(fileURL: fileURL))
        let session = makeSession(identifierSuffix: 1, updatedAt: 20)
        try await writer.indexTranscript(
            AgentTranscript(
                session: session,
                entries: [
                    makeMessage(sessionID: session.id, identifierSuffix: 1, text: "needle", at: 20)
                ]))
        let corruption = SQLiteOwnershipReadReassignment(
            databaseFileURL: fileURL,
            statements: "UPDATE context_entries SET entry_kind = 'unknown';",
            observedStatementPrefix: "WITH candidates AS")
        let reader = SQLiteContextSearch(
            existingDatabase: try SQLiteDatabase(
                fileURL: fileURL, readOnly: true, statementObserver: corruption))
        let page = try await reader.searchContext(
            forProject: session.projectID, matching: "needle", page: makePageRequest(limit: 20))
        try await corruption.verifyWriteAttempt()
        #expect(page.records.map(\.excerpt) == ["needle"])
        await #expect(throws: SQLiteContextReadFailure.malformedEntry) {
            try await reader.searchContext(
                forProject: session.projectID, matching: "needle", page: makePageRequest(limit: 20))
        }
    }
}

private struct SearchIntegrityWorkspace: AuthorizedProjectContextReading, ContextAvailabilityReading
{
    let projectID: ProjectID
    let generation = ContextReadGeneration(identifier: UUID())
    func loadAvailableGeneration() async throws -> ContextReadGeneration { generation }
    func loadAuthorizedProjectContext() async throws -> ProjectContext {
        ProjectContext(
            projectID: projectID, displayName: "Integrity", canonicalRepositoryRemote: nil,
            workspaceURL: URL(filePath: "/integrity"))
    }
}
