import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorSearch

@Suite("Conversation page ownership snapshots")
struct SQLiteConversationSnapshotTests {
    @Test("reassignment after the ownership read preserves the page and cursor snapshot")
    func reassignmentAtOwnershipBoundaryPreservesSnapshot() async throws {
        let databaseFileURL = makeDatabaseFileURL()
        defer {
            try? FileManager.default.removeItem(at: databaseFileURL.deletingLastPathComponent())
        }
        let search = try await SQLiteContextSearch(
            database: SQLiteDatabase(fileURL: databaseFileURL))
        let originalSession = makeSession(
            identifierSuffix: 900, projectIdentifierSuffix: 6, updatedAt: 300)
        let originalEntries = (1...3).map { offset in
            makeMessage(
                sessionID: originalSession.id, identifierSuffix: 900 + offset,
                text: "old ownership entry \(offset)", at: Double(offset * 100))
        }
        try await search.indexTranscript(
            AgentTranscript(session: originalSession, entries: originalEntries))
        let firstPage = try await search.loadConversationEntries(
            inSession: originalSession.id, page: makePageRequest(limit: 1))
        let firstCursor = try #require(firstPage.nextCursor)
        let reassignment = SQLiteOwnershipReadReassignment(
            databaseFileURL: databaseFileURL,
            statements: """
                BEGIN IMMEDIATE;
                UPDATE context_sessions SET project_id = '\(projectID(7).rawValue)';
                UPDATE context_entries SET body = 'new ownership entry';
                COMMIT;
                """)
        let tracedSearch = try await SQLiteContextSearch(
            database: SQLiteDatabase(fileURL: databaseFileURL, statementObserver: reassignment))

        let continuationPage = try await tracedSearch.loadConversationEntries(
            inSession: originalSession.id, page: makePageRequest(limit: 1, cursor: firstCursor))

        try await reassignment.verifyWriteAttempt()
        #expect(continuationPage.records == [originalEntries[1]])
        let continuationCursor = try #require(continuationPage.nextCursor)
        let finalPage = try await search.loadConversationEntries(
            inSession: originalSession.id,
            page: makePageRequest(limit: 1, cursor: continuationCursor))
        #expect(finalPage.records == [originalEntries[2]])
        #expect(finalPage.nextCursor == nil)

        let reassignedSession = makeSession(
            identifierSuffix: 900, projectIdentifierSuffix: 7, updatedAt: 400)
        try await search.indexTranscript(
            AgentTranscript(session: reassignedSession, entries: originalEntries))
        await #expect(throws: ContextCursorFailure.invalid) {
            try await search.loadConversationEntries(
                inSession: originalSession.id,
                page: makePageRequest(limit: 1, cursor: continuationCursor))
        }
    }

    @Test("concurrent project reassignment cannot mix cursor ownership and entries")
    func concurrentReassignmentProducesOnlyCoherentContinuation() async throws {
        for iteration in 0..<50 {
            let search = try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
            let identifierOffset = 300 + iteration * 10
            let originalSession = makeSession(
                identifierSuffix: identifierOffset,
                projectIdentifierSuffix: 6,
                updatedAt: 300)
            let reassignedSession = makeSession(
                identifierSuffix: identifierOffset,
                projectIdentifierSuffix: 7,
                updatedAt: 400)
            let firstEntry = makeMessage(
                sessionID: originalSession.id,
                identifierSuffix: identifierOffset + 1,
                text: "first ownership entry",
                at: 100)
            let originalContinuation = makeMessage(
                sessionID: originalSession.id,
                identifierSuffix: identifierOffset + 2,
                text: "old ownership continuation",
                at: 200)
            let reassignedEntry = makeMessage(
                sessionID: reassignedSession.id,
                identifierSuffix: identifierOffset + 3,
                text: "new ownership entry",
                at: 300)
            try await search.indexTranscript(
                AgentTranscript(
                    session: originalSession,
                    entries: [firstEntry, originalContinuation]))
            let firstPage = try await search.loadConversationEntries(
                inSession: originalSession.id,
                page: makePageRequest(limit: 1))
            let startGate = ConcurrentStartGate(participantCount: 2)

            let continuationTask = Task {
                await startGate.waitUntilAllParticipantsArrive()
                do {
                    let page = try await search.loadConversationEntries(
                        inSession: originalSession.id,
                        page: makePageRequest(limit: 1, cursor: firstPage.nextCursor))
                    return ConversationContinuationOutcome.accepted(page.records)
                } catch ContextCursorFailure.invalid {
                    return ConversationContinuationOutcome.rejected
                }
            }
            let reassignmentTask = Task {
                await startGate.waitUntilAllParticipantsArrive()
                await Task.yield()
                try await search.indexTranscript(
                    AgentTranscript(session: reassignedSession, entries: [reassignedEntry]))
            }

            let continuationOutcome = try await continuationTask.value
            try await reassignmentTask.value

            #expect(
                continuationOutcome == .accepted([originalContinuation])
                    || continuationOutcome == .rejected)
        }
    }
}

private enum ConversationContinuationOutcome: Sendable, Equatable {
    case accepted([ConversationEntry])
    case rejected
}

private actor ConcurrentStartGate {
    private let participantCount: Int
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func waitUntilAllParticipantsArrive() async {
        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
            guard waitingContinuations.count == participantCount else { return }

            let continuationsToResume = waitingContinuations
            waitingContinuations.removeAll()
            for waitingContinuation in continuationsToResume {
                waitingContinuation.resume()
            }
        }
    }
}
