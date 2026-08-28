import Foundation

public struct ArtifactDivergence: Sendable, Hashable, Codable {
    public let artifactID: ArtifactID
    public let localRevisionID: RevisionID
    public let remoteRevisionID: RevisionID
    public let detectedAt: Date

    public init(
        artifactID: ArtifactID,
        localRevisionID: RevisionID,
        remoteRevisionID: RevisionID,
        detectedAt: Date
    ) {
        self.artifactID = artifactID
        self.localRevisionID = localRevisionID
        self.remoteRevisionID = remoteRevisionID
        self.detectedAt = detectedAt
    }
}
