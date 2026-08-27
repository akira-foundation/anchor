import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Sync operation journal")
struct SyncOperationJournalTests {
    private let storageKey = StorageKey(rawValue: "projects/anchor/artifacts/plan")!

    private func makeRevision() throws -> ArtifactRevision {
        try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: ArtifactID(), parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("body".utf8)),
                deviceID: DeviceID(), createdAt: Date(timeIntervalSince1970: 0)
            )
        )
    }

    @Test("a recorded revision queues exactly one pending operation")
    func aRecordedRevisionQueuesExactlyOnePendingOperation() async throws {
        let journal = AppendOnlySyncOperationJournal()
        let revision = try makeRevision()

        let operation = try await journal.queueOperation(for: revision, storageKey: storageKey)

        let pending = try await journal.pendingOperations()
        #expect(pending.count == 1)
        #expect(pending.first?.id == operation.id)
        #expect(pending.first?.state == .pending)
    }

    @Test("a transition appends rather than replacing, so the history survives")
    func aTransitionAppendsRatherThanReplacing() async throws {
        let journal = AppendOnlySyncOperationJournal()
        let operation = try await journal.queueOperation(
            for: try makeRevision(), storageKey: storageKey)

        try await journal.recordTransition(of: operation.id, to: .uploading)
        try await journal.recordTransition(of: operation.id, to: .failed)
        try await journal.recordTransition(of: operation.id, to: .uploading)
        try await journal.recordTransition(of: operation.id, to: .synced)

        let history = try await journal.history(of: operation.id).map(\.state)
        #expect(history == [.pending, .uploading, .failed, .uploading, .synced])
    }

    @Test("the current state of an operation is the last thing written about it")
    func theCurrentStateIsTheLastThingWrittenAboutIt() async throws {
        let journal = AppendOnlySyncOperationJournal()
        let operation = try await journal.queueOperation(
            for: try makeRevision(), storageKey: storageKey)

        try await journal.recordTransition(of: operation.id, to: .uploading)
        try await journal.recordTransition(of: operation.id, to: .synced)

        #expect(try await journal.currentState(of: operation.id) == .synced)
        #expect(try await journal.pendingOperations().isEmpty)
    }

    @Test("an operation left uploading is put back to pending when the journal is recovered")
    func anOperationLeftUploadingIsPutBackToPending() async throws {
        let journal = AppendOnlySyncOperationJournal()
        let interrupted = try await journal.queueOperation(
            for: try makeRevision(), storageKey: storageKey)
        let finished = try await journal.queueOperation(
            for: try makeRevision(), storageKey: storageKey)
        try await journal.recordTransition(of: interrupted.id, to: .uploading)
        try await journal.recordTransition(of: finished.id, to: .synced)

        try await journal.recoverInterruptedOperations()

        #expect(try await journal.currentState(of: interrupted.id) == .pending)
        #expect(try await journal.currentState(of: finished.id) == .synced)
    }

    @Test("recovery is recorded rather than rewritten, so the interruption stays visible")
    func recoveryIsRecordedRatherThanRewritten() async throws {
        let journal = AppendOnlySyncOperationJournal()
        let operation = try await journal.queueOperation(
            for: try makeRevision(), storageKey: storageKey)
        try await journal.recordTransition(of: operation.id, to: .uploading)

        try await journal.recoverInterruptedOperations()

        #expect(
            try await journal.history(of: operation.id).map(\.state) == [
                .pending, .uploading, .pending,
            ])
    }
}
