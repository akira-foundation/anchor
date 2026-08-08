import Foundation

public struct SyncOperation: Sendable, Hashable, Codable, Identifiable {
    public let id: SyncOperationID
    public let artifactID: ArtifactID
    public let revisionID: RevisionID
    public let storageKey: StorageKey
    public let contentHash: ContentHash
    public let state: SyncOperationState
    public let queuedAt: Date

    public init(
        id: SyncOperationID,
        artifactID: ArtifactID,
        revisionID: RevisionID,
        storageKey: StorageKey,
        contentHash: ContentHash,
        state: SyncOperationState,
        queuedAt: Date
    ) {
        self.id = id
        self.artifactID = artifactID
        self.revisionID = revisionID
        self.storageKey = storageKey
        self.contentHash = contentHash
        self.state = state
        self.queuedAt = queuedAt
    }
}
