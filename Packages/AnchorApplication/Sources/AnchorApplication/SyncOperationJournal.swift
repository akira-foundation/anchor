import AnchorDomain

public protocol SyncOperationJournal: Sendable {
    func queueOperation(
        for revision: ArtifactRevision, storageKey: StorageKey
    ) async throws -> SyncOperation
    func recordTransition(
        of operationID: SyncOperationID, to state: SyncOperationState) async throws
    func history(of operationID: SyncOperationID) async throws -> [SyncOperation]
    func currentState(of operationID: SyncOperationID) async throws -> SyncOperationState?
    func pendingOperations() async throws -> [SyncOperation]
    func recoverInterruptedOperations() async throws
}
