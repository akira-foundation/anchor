import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Stored sync operation journal")
struct StoredSyncOperationJournalTests {
    private let storageKey = StorageKey(rawValue: "projects/anchor/plan")!

    private func makeRevision() throws -> ArtifactRevision {
        try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: ArtifactID(), parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("body".utf8)),
                deviceID: DeviceID(), createdAt: Date(timeIntervalSince1970: 0)
            )
        )
    }

    @Test("a queued operation is pending and survives a new journal")
    func aQueuedOperationIsPendingAndSurvivesANewJournal() async throws {
        let storage = InMemoryStorageProvider()
        let queued = try await StoredSyncOperationJournal(storage: storage)
            .queueOperation(for: try makeRevision(), storageKey: storageKey)

        let reopened = StoredSyncOperationJournal(storage: storage)
        #expect(try await reopened.currentState(of: queued.id) == .pending)
        #expect(try await reopened.pendingOperations().map(\.id) == [queued.id])
    }

    @Test("the history keeps every transition in order")
    func theHistoryKeepsEveryTransitionInOrder() async throws {
        let journal = StoredSyncOperationJournal(storage: InMemoryStorageProvider())
        let queued = try await journal.queueOperation(
            for: try makeRevision(), storageKey: storageKey)

        try await journal.recordTransition(of: queued.id, to: .uploading)
        try await journal.recordTransition(of: queued.id, to: .failed)
        try await journal.recordTransition(of: queued.id, to: .uploading)
        try await journal.recordTransition(of: queued.id, to: .synced)

        #expect(
            try await journal.history(of: queued.id).map(\.state) == [
                .pending, .uploading, .failed, .uploading, .synced,
            ])
    }

    @Test("an interrupted operation is recovered without erasing the interruption")
    func anInterruptedOperationIsRecoveredWithoutErasingTheInterruption() async throws {
        let storage = InMemoryStorageProvider()
        let journal = StoredSyncOperationJournal(storage: storage)
        let interrupted = try await journal.queueOperation(
            for: try makeRevision(), storageKey: storageKey)
        try await journal.recordTransition(of: interrupted.id, to: .uploading)

        try await StoredSyncOperationJournal(storage: storage).recoverInterruptedOperations()

        #expect(try await journal.currentState(of: interrupted.id) == .pending)
        #expect(
            try await journal.history(of: interrupted.id).map(\.state) == [
                .pending, .uploading, .pending,
            ])
    }

    @Test("a synced operation is left alone by recovery")
    func aSyncedOperationIsLeftAloneByRecovery() async throws {
        let journal = StoredSyncOperationJournal(storage: InMemoryStorageProvider())
        let finished = try await journal.queueOperation(
            for: try makeRevision(), storageKey: storageKey)
        try await journal.recordTransition(of: finished.id, to: .synced)

        try await journal.recoverInterruptedOperations()

        #expect(try await journal.currentState(of: finished.id) == .synced)
    }
}
