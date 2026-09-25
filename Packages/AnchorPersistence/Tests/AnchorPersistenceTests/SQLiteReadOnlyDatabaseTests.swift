import Foundation
import Testing

@testable import AnchorPersistence

@Suite("Read-only SQLite connections")
struct SQLiteReadOnlyDatabaseTests {
    @Test("a read-only connection permits snapshots and rejects writes")
    func readOnlyConnectionRejectsWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "anchor-read-only-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "context.sqlite")
        let writer = try SQLiteDatabase(fileURL: fileURL)
        try await writer.execute(
            "CREATE TABLE evidence (name TEXT); INSERT INTO evidence VALUES ('saved');")
        let reader = try SQLiteDatabase(fileURL: fileURL, readOnly: true)
        let rows = try await reader.withinTransaction { try $0.run("SELECT name FROM evidence;") }
        #expect(rows.first?["name"]?.text == "saved")
        await #expect(throws: (any Error).self) { try await reader.run("DELETE FROM evidence;") }
        let absentURL = directory.appending(path: "absent.sqlite")
        #expect(throws: (any Error).self) { try SQLiteDatabase(fileURL: absentURL, readOnly: true) }
        #expect(!FileManager.default.fileExists(atPath: absentURL.path()))
    }
}
