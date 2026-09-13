import AnchorDomain

public struct ArtifactContextRecord: Sendable, Hashable {
    public let artifact: Artifact
    public let latestRevision: ArtifactRevision?

    public init?(artifact: Artifact, latestRevision: ArtifactRevision?) {
        if let latestRevision, latestRevision.artifactID != artifact.id {
            return nil
        }

        self.artifact = artifact
        self.latestRevision = latestRevision
    }
}

public protocol ArtifactContextReading: Sendable {
    func listArtifacts(
        forProject projectID: ProjectID,
        provider: AgentProvider?,
        page: ContextPageRequest
    ) async throws -> ContextPage<ArtifactContextRecord>

    func loadArtifact(withIdentifier artifactID: ArtifactID) async throws -> ArtifactContextRecord?
}

public protocol ArtifactContextIndexing: Sendable {
    func indexArtifactRevisions(_ revisions: [RecordedArtifactRevision]) async throws
}
