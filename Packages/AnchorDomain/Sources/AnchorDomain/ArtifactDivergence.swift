import Foundation

public enum ArtifactDivergenceResolution: String, Sendable, Hashable, Codable {
    case convergedOnIdenticalContent
    case awaitingDecision
}

public struct ArtifactDivergence: Sendable, Hashable, Codable {
    public let artifactID: ArtifactID
    public let localRevisionID: RevisionID
    public let remoteRevisionID: RevisionID
    public let resolution: ArtifactDivergenceResolution
    public let detectedAt: Date

    public init(
        artifactID: ArtifactID,
        localRevisionID: RevisionID,
        remoteRevisionID: RevisionID,
        resolution: ArtifactDivergenceResolution,
        detectedAt: Date
    ) {
        self.artifactID = artifactID
        self.localRevisionID = localRevisionID
        self.remoteRevisionID = remoteRevisionID
        self.resolution = resolution
        self.detectedAt = detectedAt
    }
}
