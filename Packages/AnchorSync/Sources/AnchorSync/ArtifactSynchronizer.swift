import AnchorApplication
import AnchorDomain
import Foundation

public actor ArtifactSynchronizer: ArtifactRevisionSynchronizing {
    private let local: RevisionStore
    private let remote: RevisionStore
    private let operations: any SyncOperationJournal
    private let failures: any SyncFailureClassifying
    private let receiver: RemoteRevisionReceiver

    public init(
        local: RevisionStore,
        remote: RevisionStore,
        operations: any SyncOperationJournal,
        failures: any SyncFailureClassifying,
        feed: any RemoteRevisionFeed,
        cursors: any SyncCursorStore,
        divergences: any ArtifactDivergenceJournal,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.local = local
        self.remote = remote
        self.operations = operations
        self.failures = failures
        self.receiver = RemoteRevisionReceiver(
            local: local, remote: remote, feed: feed, cursors: cursors,
            divergences: divergences, now: now
        )
    }

    public func synchronizePendingArtifactRevisions() async throws {
        for operation in try await operations.pendingOperations() {
            try await upload(operation)
        }

        try await receiver.receiveRemoteRevisions()
    }

    private func upload(_ operation: SyncOperation) async throws {
        try await operations.recordTransition(of: operation.id, to: .uploading)

        do {
            try await transfer(operation)
        } catch {
            let reached: SyncOperationState = failures.isWorthRetrying(error) ? .pending : .failed
            try await operations.recordTransition(of: operation.id, to: reached)

            return
        }

        try await operations.recordTransition(of: operation.id, to: .synced)
    }

    private func transfer(_ operation: SyncOperation) async throws {
        guard let revision = try await local.journal.revision(withIdentifier: operation.revisionID),
            let content = try await local.contents.content(forRevision: operation.revisionID)
        else {
            throw ArtifactSynchronizationFailure.revisionIsNoLongerHeldLocally(operation.revisionID)
        }

        try await remote.contents.storeContent(content, forRevision: revision.id)
        try await remote.journal.recordRevision(revision)
    }

}

public enum ArtifactSynchronizationFailure: Error, Sendable, Equatable {
    case revisionIsNoLongerHeldLocally(RevisionID)
    case revisionIsNoLongerHeldRemotely(RevisionID)
}
