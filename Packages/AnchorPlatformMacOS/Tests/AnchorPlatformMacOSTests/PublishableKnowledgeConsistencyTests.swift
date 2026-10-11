import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import Foundation
import SQLite3
import Synchronization
import Testing

@testable import AnchorPlatformMacOS

@Suite("Publishable knowledge consistency")
struct PublishableKnowledgeConsistencyTests {
    private let workspaceURL = URL(filePath: "/Users/dev/anchor")
    private let projectID = ProjectID()

    @Test("a source recorded between the knowledge reads never appears without its entries")
    func sourceRecordedDuringReadStaysConsistent() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "anchor-knowledge-consistency-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let databaseFileURL = directoryURL.appending(path: "context.sqlite")
        try await seedProjectWithKnowledge(in: SQLiteDatabase(fileURL: databaseFileURL))
        let lateEntryWrite = try LateKnowledgeEntryWrite(
            databaseFileURL: databaseFileURL, projectID: projectID,
            source: .session(SessionID()))
        let observedDatabase = try SQLiteDatabase(
            fileURL: databaseFileURL, statementObserver: lateEntryWrite)

        let context = try #require(
            try await PersistentPublishableContextReader(database: observedDatabase)
                .loadPublishableProjectContext(forWorkspaceAt: workspaceURL))

        let attemptStatus = try #require(lateEntryWrite.attemptStatus)
        #expect(attemptStatus == SQLITE_OK || attemptStatus == SQLITE_BUSY)
        #expect(Set(context.knowledgeSources) == Set(context.knowledgeEntries.map(\.source)))
    }

    private func seedProjectWithKnowledge(in database: SQLiteDatabase) async throws {
        let artifacts = try await SQLiteArtifactContextStore(database: database)
        let knowledge = try await SQLiteKnowledgeStore(database: database)
        try await artifacts.recordProjectContext(
            ProjectContext(
                projectID: projectID, displayName: "Anchor", canonicalRepositoryRemote: nil,
                workspaceURL: workspaceURL))
        let source = KnowledgeEntrySource.session(SessionID())
        try await knowledge.recordEntries(
            [
                KnowledgeEntry(
                    id: KnowledgeEntryID(), projectID: projectID, kind: .todo,
                    summaryText: "Ship 30", source: source,
                    sourceContentHash: .digest(of: Data("s".utf8)),
                    createdAt: Date(timeIntervalSince1970: 20))
            ], supersedingEntriesFrom: source)
    }
}

private final class LateKnowledgeEntryWrite: SQLiteStatementObserving {
    private static let observedStatementPrefix = "SELECT id, project_id, kind, summary_text"

    private let databaseFileURL: URL
    private let insertStatement: String
    private let recordedStatus = Mutex<Int32?>(nil)

    init(databaseFileURL: URL, projectID: ProjectID, source: KnowledgeEntrySource) throws {
        self.databaseFileURL = databaseFileURL
        let encodedSource = String(decoding: try JSONEncoder().encode(source), as: UTF8.self)
        insertStatement = """
            INSERT INTO knowledge_entries (
                id, project_id, kind, summary_text, source, source_content_hash, state, created_at
            ) VALUES (
                '\(KnowledgeEntryID().rawValue)', '\(projectID.rawValue)', 'todo', 'Late',
                '\(encodedSource)', '\(ContentHash.digest(of: Data("late".utf8)).rawValue)',
                'current', 10
            );
            """
    }

    var attemptStatus: Int32? { recordedStatus.withLock { $0 } }

    func recordCompletion(ofStatement statement: String) {
        guard statement.hasPrefix(Self.observedStatementPrefix), attemptStatus == nil else {
            return
        }
        var writerConnection: OpaquePointer?
        let openedStatus = sqlite3_open(databaseFileURL.path, &writerConnection)
        defer { sqlite3_close(writerConnection) }
        let status =
            openedStatus == SQLITE_OK
            ? sqlite3_exec(writerConnection, insertStatement, nil, nil, nil) : openedStatus
        recordedStatus.withLock { $0 = status }
    }
}
