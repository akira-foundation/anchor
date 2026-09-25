import AnchorPersistence
import Dispatch
import Foundation
import Testing

@Suite("SQLite database transactions")
struct SQLiteDatabaseTransactionTests {
    private enum TransactionFailure: Error {
        case interrupted
    }

    @Test("a thrown transaction leaves no partial rows")
    func thrownTransactionLeavesNoPartialRows() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        try await database.execute("CREATE TABLE records (identifier INTEGER PRIMARY KEY);")

        await #expect(throws: TransactionFailure.self) {
            try await database.withinTransaction { isolatedDatabase in
                try isolatedDatabase.run("INSERT INTO records (identifier) VALUES (1);")
                throw TransactionFailure.interrupted
            }
        }

        #expect(try await rowCount(in: database) == 0)
    }

    @Test("a successful transaction publishes all rows together")
    func successfulTransactionPublishesAllRowsTogether() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        try await database.execute("CREATE TABLE records (identifier INTEGER PRIMARY KEY);")

        try await database.withinTransaction { isolatedDatabase in
            try isolatedDatabase.run("INSERT INTO records (identifier) VALUES (1);")
            try isolatedDatabase.run("INSERT INTO records (identifier) VALUES (2);")
        }

        #expect(try await rowCount(in: database) == 2)
    }

    @Test("a file-backed transaction publishes rows atomically to a concurrent reader")
    func fileBackedTransactionPublishesRowsAtomicallyToConcurrentReader() async throws {
        let fileURL = makeFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let writer = try SQLiteDatabase(fileURL: fileURL)
        try await writer.execute("CREATE TABLE records (identifier INTEGER PRIMARY KEY);")
        let reader = try SQLiteDatabase(fileURL: fileURL)
        let firstTransactionInsertEvents = AsyncStream<Void>.makeStream()
        let readerCompleted = DispatchSemaphore(value: 0)

        let writerTransaction = Task.detached {
            try await writer.withinTransaction { isolatedDatabase in
                try isolatedDatabase.run("INSERT INTO records (identifier) VALUES (1);")
                firstTransactionInsertEvents.continuation.yield()
                readerCompleted.wait()
                try isolatedDatabase.run("INSERT INTO records (identifier) VALUES (2);")
            }
        }
        let readerRows = Task.detached { () throws -> Int64 in
            var firstInsertIterator = firstTransactionInsertEvents.stream.makeAsyncIterator()
            _ = await firstInsertIterator.next()
            defer { readerCompleted.signal() }
            let countRows = try await reader.run("SELECT COUNT(*) AS count FROM records;")
            return try #require(countRows.first?["count"]?.integer)
        }

        let rowsBeforeCommit = try await readerRows.value
        try await writerTransaction.value

        #expect(rowsBeforeCommit == 0)
        #expect(try await rowCount(in: reader) == 2)
        #expect(try await rowCount(in: writer) == 2)
    }

    @Test("a second connection reads while the first connection remains open")
    func secondConnectionReadsWhileWriterRemainsOpen() async throws {
        let fileURL = makeFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let writer = try SQLiteDatabase(fileURL: fileURL)
        try await writer.execute("CREATE TABLE records (identifier INTEGER PRIMARY KEY);")
        try await writer.run("INSERT INTO records (identifier) VALUES (1);")

        let reader = try SQLiteDatabase(fileURL: fileURL)

        #expect(try await rowCount(in: reader) == 1)
    }

    @Test("a file database uses WAL journal mode")
    func fileDatabaseUsesWriteAheadLogging() async throws {
        let fileURL = makeFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let database = try SQLiteDatabase(fileURL: fileURL)
        let journalRows = try await database.run("PRAGMA journal_mode;")

        #expect(journalRows.first?["journal_mode"] == .text("wal"))
    }

    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-transactions-\(UUID().uuidString)/index.sqlite")
    }

    private func rowCount(in database: SQLiteDatabase) async throws -> Int64 {
        let countRows = try await database.run("SELECT COUNT(*) AS count FROM records;")
        let count = try #require(countRows.first?["count"]?.integer)
        return count
    }
}
