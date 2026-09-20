import AnchorPersistence
import Foundation
import SQLite3
import Testing

final class SQLiteOwnershipReadReassignment: SQLiteStatementObserving {
    private let databaseFileURL: URL
    private let statements: String
    private let observedStatementPrefix: String
    private let attempts = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))

    init(
        databaseFileURL: URL, statements: String,
        observedStatementPrefix: String =
            "SELECT project_id FROM context_sessions WHERE session_id = ? LIMIT 1;"
    ) {
        self.databaseFileURL = databaseFileURL
        self.statements = statements
        self.observedStatementPrefix = observedStatementPrefix
    }

    func recordCompletion(ofStatement statement: String) {
        guard statement.hasPrefix(observedStatementPrefix)
        else { return }
        var writerConnection: OpaquePointer?
        let openedStatus = sqlite3_open(databaseFileURL.path, &writerConnection)
        defer { sqlite3_close(writerConnection) }
        guard openedStatus == SQLITE_OK else {
            attempts.continuation.yield(openedStatus)
            return
        }
        let attemptedStatus = sqlite3_exec(writerConnection, statements, nil, nil, nil)
        attempts.continuation.yield(attemptedStatus)
    }

    func verifyWriteAttempt() async throws {
        attempts.continuation.finish()
        var iterator = attempts.stream.makeAsyncIterator()
        let status = try #require(await iterator.next())
        #expect(status == SQLITE_OK || status == SQLITE_BUSY)
    }
}
