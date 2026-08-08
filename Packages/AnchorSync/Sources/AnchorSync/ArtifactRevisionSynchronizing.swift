public protocol ArtifactRevisionSynchronizing: Sendable {
    func synchronizePendingArtifactRevisions() async throws
}
