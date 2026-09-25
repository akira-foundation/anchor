import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorSearch

@Suite("Reading durable session context")
struct SQLiteSessionContextReadingTests {
    @Test("a transcript survives closing and reopening the database")
    func transcriptSurvivesDatabaseReopen() async throws {
        let databaseFileURL = makeDatabaseFileURL()
        defer {
            try? FileManager.default.removeItem(at: databaseFileURL.deletingLastPathComponent())
        }
        let session = makeSession(identifierSuffix: 1, updatedAt: 300)
        let entries = [
            makeMessage(
                sessionID: session.id, identifierSuffix: 11, text: "durable decision", at: 100),
            makeActivity(sessionID: session.id, identifierSuffix: 12, at: 200),
        ]

        try await index(AgentTranscript(session: session, entries: entries), at: databaseFileURL)
        let reopenedSearch = try await SQLiteContextSearch(
            database: try SQLiteDatabase(fileURL: databaseFileURL))

        #expect(
            try await reopenedSearch.loadSession(withIdentifier: session.id)?.session == session)
        #expect(
            try await reopenedSearch.loadConversationEntries(
                inSession: session.id, page: makePageRequest(limit: 10)
            ).records == entries
        )
    }

    @Test("reindexing replaces metadata entries and FTS rows atomically")
    func reindexingReplacesTheWholeSession() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let originalSession = makeSession(identifierSuffix: 1, provider: .claude, updatedAt: 200)
        let replacementSession = AgentSession(
            id: originalSession.id,
            projectID: originalSession.projectID,
            provider: .codex,
            startedAt: Date(timeIntervalSince1970: 20),
            updatedAt: Date(timeIntervalSince1970: 400)
        )
        let replacementEntry = makeMessage(
            sessionID: originalSession.id, identifierSuffix: 22,
            text: "replacement-canonical-token", at: 300)
        let blockingSession = makeSession(identifierSuffix: 2, updatedAt: 250)
        let blockingEntry = makeMessage(
            sessionID: blockingSession.id, identifierSuffix: 99,
            text: "blocking-canonical-token", at: 150)

        try await search.indexTranscript(
            AgentTranscript(
                session: originalSession,
                entries: [
                    makeMessage(
                        sessionID: originalSession.id, identifierSuffix: 21,
                        text: "obsolete-canonical-token", at: 100)
                ]
            ))
        try await search.indexTranscript(
            AgentTranscript(session: replacementSession, entries: [replacementEntry]))
        try await search.indexTranscript(
            AgentTranscript(session: blockingSession, entries: [blockingEntry]))

        await #expect(throws: SQLiteDatabase.Failure.self) {
            try await search.indexTranscript(
                AgentTranscript(
                    session: originalSession,
                    entries: [
                        makeMessage(
                            sessionID: originalSession.id, identifierSuffix: 23,
                            text: "partial-canonical-token", at: 350),
                        makeMessage(
                            sessionID: originalSession.id, identifierSuffix: 99,
                            text: "collision-canonical-token", at: 360),
                    ]))
        }

        #expect(
            try await search.loadSession(withIdentifier: originalSession.id)?.session
                == replacementSession)
        #expect(
            try await search.loadConversationEntries(
                inSession: originalSession.id, page: makePageRequest(limit: 10)
            ).records == [replacementEntry]
        )
        #expect(
            try await search.findContext(matching: "obsolete-canonical-token", limit: 10).isEmpty)
        #expect(
            try await search.findContext(matching: "partial-canonical-token", limit: 10).isEmpty)
        #expect(
            try await search.findContext(matching: "replacement-canonical-token", limit: 10).count
                == 1)
    }

    @Test("session pages are newest first with identifier tie breaking")
    func sessionPagesUseStableOrdering() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let oldest = makeSession(identifierSuffix: 4, updatedAt: 100)
        let newestThird = makeSession(identifierSuffix: 3, updatedAt: 200)
        let newestFirst = makeSession(identifierSuffix: 1, updatedAt: 200)
        let newestSecond = makeSession(identifierSuffix: 2, updatedAt: 200)
        for session in [oldest, newestThird, newestFirst, newestSecond] {
            try await search.indexTranscript(AgentTranscript(session: session, entries: []))
        }

        let firstPage = try await search.listSessions(
            forProject: oldest.projectID, provider: nil, page: makePageRequest(limit: 2))
        let secondPage = try await search.listSessions(
            forProject: oldest.projectID,
            provider: nil,
            page: makePageRequest(limit: 2, cursor: firstPage.nextCursor))

        #expect(firstPage.records.map(\.session.id) == [newestFirst.id, newestSecond.id])
        #expect(secondPage.records.map(\.session.id) == [newestThird.id, oldest.id])
        #expect(secondPage.nextCursor == nil)
    }

    @Test("message cursors cannot be reused for another session")
    func messageCursorCannotCrossSessions() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let firstSession = makeSession(identifierSuffix: 1, updatedAt: 200)
        let secondSession = makeSession(identifierSuffix: 2, updatedAt: 200)
        try await search.indexTranscript(
            AgentTranscript(
                session: firstSession,
                entries: [
                    makeMessage(
                        sessionID: firstSession.id, identifierSuffix: 31, text: "first", at: 100),
                    makeMessage(
                        sessionID: firstSession.id, identifierSuffix: 32, text: "second", at: 200),
                ]))
        try await search.indexTranscript(AgentTranscript(session: secondSession, entries: []))
        let firstPage = try await search.loadConversationEntries(
            inSession: firstSession.id, page: makePageRequest(limit: 1))

        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.loadConversationEntries(
                inSession: secondSession.id,
                page: makePageRequest(limit: 1, cursor: firstPage.nextCursor))
        }
    }

    @Test("raw provider secret text never enters the canonical fixture")
    func indexedFixtureContainsOnlyRedactedCanonicalText() async throws {
        let databaseFileURL = makeDatabaseFileURL()
        defer {
            try? FileManager.default.removeItem(at: databaseFileURL.deletingLastPathComponent())
        }
        let session = makeSession(identifierSuffix: 1, updatedAt: 200)
        let originalProviderSecret = "sk-live-provider-fixture-secret"
        let canonicalEntry = makeMessage(
            sessionID: session.id, identifierSuffix: 41,
            text: "credential [redacted:api-key]", at: 100)

        try await index(
            AgentTranscript(session: session, entries: [canonicalEntry]), at: databaseFileURL)
        let reopenedSearch = try await SQLiteContextSearch(
            database: try SQLiteDatabase(fileURL: databaseFileURL))
        let persistedEntries = try await reopenedSearch.loadConversationEntries(
            inSession: session.id, page: makePageRequest(limit: 10)
        ).records

        #expect(
            try await reopenedSearch.findContext(matching: originalProviderSecret, limit: 10)
                .isEmpty)
        #expect(persistedEntries == [canonicalEntry])
        #expect(!persistedEntries.contains { entryBody($0).contains(originalProviderSecret) })
    }

    @Test("fractional session and entry timestamps survive persistence")
    func fractionalTimestampsSurvivePersistence() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let session = makeSession(
            identifierSuffix: 51, startedAt: 10.123456, updatedAt: 20.654321)
        let entries = [
            makeMessage(
                sessionID: session.id, identifierSuffix: 52,
                text: "fractional message", at: 100.123456),
            makeActivity(sessionID: session.id, identifierSuffix: 53, at: 100.987654),
        ]
        try await search.indexTranscript(AgentTranscript(session: session, entries: entries))

        let restoredSession = try #require(
            await search.loadSession(withIdentifier: session.id)?.session)
        let restoredEntries = try await search.loadConversationEntries(
            inSession: session.id, page: makePageRequest(limit: 10)
        ).records

        #expect(abs(restoredSession.startedAt.timeIntervalSince1970 - 10.123456) < 0.000001)
        #expect(abs(restoredSession.updatedAt.timeIntervalSince1970 - 20.654321) < 0.000001)
        #expect(abs(restoredEntries[0].timestamp.timeIntervalSince1970 - 100.123456) < 0.000001)
        #expect(abs(restoredEntries[1].timestamp.timeIntervalSince1970 - 100.987654) < 0.000001)
    }

    @Test("fractional timestamps outrank opposing identifiers across pages")
    func fractionalTimestampsDeterminePaginationOrder() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let session = makeSession(identifierSuffix: 61, updatedAt: 300)
        let earlierLargerIdentifier = makeMessage(
            sessionID: session.id, identifierSuffix: 90, text: "earlier", at: 100.1)
        let laterSmallerIdentifier = makeMessage(
            sessionID: session.id, identifierSuffix: 10, text: "later", at: 100.9)
        try await search.indexTranscript(
            AgentTranscript(
                session: session, entries: [laterSmallerIdentifier, earlierLargerIdentifier]))

        let firstPage = try await search.loadConversationEntries(
            inSession: session.id, page: makePageRequest(limit: 1))
        let secondPage = try await search.loadConversationEntries(
            inSession: session.id,
            page: makePageRequest(limit: 1, cursor: firstPage.nextCursor))

        #expect(firstPage.records == [earlierLargerIdentifier])
        #expect(secondPage.records == [laterSmallerIdentifier])
    }

    @Test("a message cursor becomes invalid when its session moves projects")
    func messageCursorCannotSurviveProjectReassignment() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let originalSession = makeSession(
            identifierSuffix: 71, projectIdentifierSuffix: 8, updatedAt: 300)
        let reassignedSession = makeSession(
            identifierSuffix: 71, projectIdentifierSuffix: 9, updatedAt: 400)
        try await search.indexTranscript(
            AgentTranscript(
                session: originalSession,
                entries: [
                    makeMessage(
                        sessionID: originalSession.id, identifierSuffix: 72,
                        text: "first project entry", at: 100),
                    makeMessage(
                        sessionID: originalSession.id, identifierSuffix: 73,
                        text: "first project continuation", at: 200),
                ]))
        let originalPage = try await search.loadConversationEntries(
            inSession: originalSession.id, page: makePageRequest(limit: 1))
        try await search.indexTranscript(
            AgentTranscript(
                session: reassignedSession,
                entries: [
                    makeMessage(
                        sessionID: reassignedSession.id, identifierSuffix: 74,
                        text: "reassigned entry", at: 300)
                ]))

        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.loadConversationEntries(
                inSession: reassignedSession.id,
                page: makePageRequest(limit: 1, cursor: originalPage.nextCursor))
        }
    }

    @Test("mixed entries continue stably across an equal timestamp")
    func mixedEntriesContinueAcrossEqualTimestamps() async throws {
        let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
        let session = makeSession(identifierSuffix: 81, updatedAt: 300)
        let message = makeMessage(
            sessionID: session.id, identifierSuffix: 82, text: "message entry", at: 100.5)
        let activity = makeActivity(sessionID: session.id, identifierSuffix: 83, at: 100.5)
        try await search.indexTranscript(
            AgentTranscript(session: session, entries: [activity, message]))

        let firstPage = try await search.loadConversationEntries(
            inSession: session.id, page: makePageRequest(limit: 1))
        let secondPage = try await search.loadConversationEntries(
            inSession: session.id,
            page: makePageRequest(limit: 1, cursor: firstPage.nextCursor))

        #expect(firstPage.records == [message])
        #expect(secondPage.records == [activity])
    }
}
