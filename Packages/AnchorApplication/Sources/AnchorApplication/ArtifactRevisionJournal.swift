import AnchorDomain

public protocol ArtifactRevisionJournal: Sendable {
    func latestRevision(forArtifact artifactID: ArtifactID) async throws -> ArtifactRevision?
    func revision(withIdentifier revisionID: RevisionID) async throws -> ArtifactRevision?
    func recordRevision(_ revision: ArtifactRevision) async throws
}
