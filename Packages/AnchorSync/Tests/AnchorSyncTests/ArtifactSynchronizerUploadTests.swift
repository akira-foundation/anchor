import AnchorApplication
import AnchorDomain
import AnchorSync
import Foundation
import Testing

@Suite("Uploading pending revisions")
struct ArtifactSynchronizerUploadTests {
    private func makeStores(
        remoteJournalFailure: (any Error)? = nil
    ) -> (local: RevisionStore, remote: RevisionStore) {
        (
            RevisionStore(journal: InMemoryRevisionJournal(), contents: InMemoryContentStore()),
            RevisionStore(
                journal: InMemoryRevisionJournal(failing: remoteJournalFailure),
                contents: InMemoryContentStore()
            )
        )
    }

    private func queue(
        _ revision: ArtifactRevision,
        contents: Data,
        into stores: (local: RevisionStore, remote: RevisionStore),
        operations: any SyncOperationJournal
    ) async throws -> SyncOperation {
        try await stores.local.contents.storeContent(contents, forRevision: revision.id)
        try await stores.local.journal.recordRevision(revision)

        return try await operations.queueOperation(
            for: revision, storageKey: try #require(StorageKey(rawValue: "docs/guide.md"))
        )
    }

    @Test("a pending revision reaches the other side, contents and all")
    func aPendingRevisionReachesTheOtherSideContentsAndAll() async throws {
        let stores = makeStores()
        let operations = AppendOnlySyncOperationJournal()
        let revision = try makeRevision(contents: "anchor")
        let operation = try await queue(
            revision, contents: Data("anchor".utf8), into: stores, operations: operations)

        try await ArtifactSynchronizer(
            local: stores.local, remote: stores.remote, operations: operations,
            failures: StubFailureClassifier()
        ).synchronizePendingArtifactRevisions()

        #expect(
            try await stores.remote.journal.revision(withIdentifier: revision.id) == revision)
        #expect(
            try await stores.remote.contents.content(forRevision: revision.id)
                == Data("anchor".utf8))
        #expect(try await operations.currentState(of: operation.id) == .synced)
    }

    @Test("a transient failure leaves the operation pending for the next run")
    func aTransientFailureLeavesTheOperationPendingForTheNextRun() async throws {
        let stores = makeStores(remoteJournalFailure: StubFailure(isTransient: true))
        let operations = AppendOnlySyncOperationJournal()
        let operation = try await queue(
            try makeRevision(contents: "anchor"), contents: Data("anchor".utf8),
            into: stores, operations: operations
        )

        try await ArtifactSynchronizer(
            local: stores.local, remote: stores.remote, operations: operations,
            failures: StubFailureClassifier()
        ).synchronizePendingArtifactRevisions()

        #expect(try await operations.currentState(of: operation.id) == .pending)
    }

    @Test("a failure no retry can fix stops the operation instead of repeating it")
    func aFailureNoRetryCanFixStopsTheOperationInsteadOfRepeatingIt() async throws {
        let stores = makeStores(remoteJournalFailure: StubFailure(isTransient: false))
        let operations = AppendOnlySyncOperationJournal()
        let operation = try await queue(
            try makeRevision(contents: "anchor"), contents: Data("anchor".utf8),
            into: stores, operations: operations
        )

        try await ArtifactSynchronizer(
            local: stores.local, remote: stores.remote, operations: operations,
            failures: StubFailureClassifier()
        ).synchronizePendingArtifactRevisions()

        #expect(try await operations.currentState(of: operation.id) == .failed)
    }

    @Test("an operation whose revision no longer exists locally is not retried forever")
    func anOperationWhoseRevisionNoLongerExistsLocallyIsNotRetriedForever() async throws {
        let stores = makeStores()
        let operations = AppendOnlySyncOperationJournal()
        let operation = try await operations.queueOperation(
            for: try makeRevision(contents: "gone"),
            storageKey: try #require(StorageKey(rawValue: "docs/guide.md"))
        )

        try await ArtifactSynchronizer(
            local: stores.local, remote: stores.remote, operations: operations,
            failures: StubFailureClassifier()
        ).synchronizePendingArtifactRevisions()

        #expect(try await operations.currentState(of: operation.id) == .failed)
    }
}
