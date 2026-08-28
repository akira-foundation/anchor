import AnchorApplication
import AnchorDomain
import Foundation

public actor ArtifactSynchronizer: ArtifactRevisionSynchronizing {
    private let local: RevisionStore
    private let remote: RevisionStore
    private let operations: any SyncOperationJournal
    private let failures: any SyncFailureClassifying
    private let feed: any RemoteRevisionFeed
    private let cursors: any SyncCursorStore
    private let divergences: any ArtifactDivergenceJournal
    private let now: @Sendable () -> Date

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
        self.feed = feed
        self.cursors = cursors
        self.divergences = divergences
        self.now = now
    }

    public func synchronizePendingArtifactRevisions() async throws {
        for operation in try await operations.pendingOperations() {
            try await upload(operation)
        }

        try await receiveRemoteRevisions()
    }

    private func receiveRemoteRevisions() async throws {
        let page = try await feed.revisions(after: try await cursors.cursor())

        for revision in parentsBeforeChildren(page.revisions) {
            try await receive(revision)
        }

        guard let reached = page.cursor else { return }

        try await cursors.recordCursor(reached)
    }

    private func parentsBeforeChildren(
        _ revisions: [ArtifactRevision]
    ) -> [ArtifactRevision] {
        var remaining = revisions
        var ordered: [ArtifactRevision] = []
        var placed: Set<RevisionID> = []

        while !remaining.isEmpty {
            let ready = remaining.filter { revision in
                guard let parentID = revision.parentRevisionID else { return true }

                return placed.contains(parentID)
                    || !remaining.contains { candidate in candidate.id == parentID }
            }

            guard !ready.isEmpty else { return ordered + remaining }

            ordered += ready
            placed.formUnion(ready.map(\.id))
            remaining.removeAll { placed.contains($0.id) }
        }

        return ordered
    }

    private func receive(_ remoteRevision: ArtifactRevision) async throws {
        guard try await local.journal.revision(withIdentifier: remoteRevision.id) == nil else {
            return
        }

        let localLatest = try await local.journal.latestRevision(
            forArtifact: remoteRevision.artifactID)

        guard continues(remoteRevision, after: localLatest) else {
            try await divergences.recordDivergence(
                ArtifactDivergence(
                    artifactID: remoteRevision.artifactID,
                    localRevisionID: localLatest?.id ?? remoteRevision.id,
                    remoteRevisionID: remoteRevision.id,
                    detectedAt: now()
                )
            )

            return
        }

        guard let content = try await remote.contents.content(forRevision: remoteRevision.id) else {
            throw ArtifactSynchronizationFailure.revisionIsNoLongerHeldRemotely(remoteRevision.id)
        }

        try await local.contents.storeContent(content, forRevision: remoteRevision.id)
        try await local.journal.recordRevision(remoteRevision)
    }

    private func continues(
        _ remoteRevision: ArtifactRevision, after localLatest: ArtifactRevision?
    ) -> Bool {
        guard let localLatest else { return true }

        return remoteRevision.parentRevisionID == localLatest.id
            || remoteRevision.parentRevisionID == nil
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
