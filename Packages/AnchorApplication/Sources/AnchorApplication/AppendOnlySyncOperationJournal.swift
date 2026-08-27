import AnchorDomain
import Foundation

public actor AppendOnlySyncOperationJournal: SyncOperationJournal {
    private var entries: [SyncOperation] = []

    public init() {}

    public func queueOperation(
        for revision: ArtifactRevision,
        storageKey: StorageKey
    ) async throws -> SyncOperation {
        let operation = SyncOperation(
            id: SyncOperationID(),
            artifactID: revision.artifactID,
            revisionID: revision.id,
            storageKey: storageKey,
            contentHash: revision.contentHash,
            state: .pending,
            queuedAt: Date()
        )
        entries.append(operation)

        return operation
    }

    public func recordTransition(
        of operationID: SyncOperationID, to state: SyncOperationState
    ) async throws {
        guard let latest = latestEntry(of: operationID) else { return }

        entries.append(
            SyncOperation(
                id: latest.id,
                artifactID: latest.artifactID,
                revisionID: latest.revisionID,
                storageKey: latest.storageKey,
                contentHash: latest.contentHash,
                state: state,
                queuedAt: latest.queuedAt
            )
        )
    }

    public func history(of operationID: SyncOperationID) async throws -> [SyncOperation] {
        entries.filter { $0.id == operationID }
    }

    public func currentState(of operationID: SyncOperationID) async throws -> SyncOperationState? {
        latestEntry(of: operationID)?.state
    }

    public func pendingOperations() async throws -> [SyncOperation] {
        latestEntryPerOperation().filter { $0.state == .pending }
    }

    public func recoverInterruptedOperations() async throws {
        for interrupted in latestEntryPerOperation() where interrupted.state == .uploading {
            try await recordTransition(of: interrupted.id, to: .pending)
        }
    }

    private func latestEntry(of operationID: SyncOperationID) -> SyncOperation? {
        entries.last { $0.id == operationID }
    }

    private func latestEntryPerOperation() -> [SyncOperation] {
        var latestByID: [SyncOperationID: SyncOperation] = [:]
        for entry in entries { latestByID[entry.id] = entry }

        return Array(latestByID.values)
    }
}
