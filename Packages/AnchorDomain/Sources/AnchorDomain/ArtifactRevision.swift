import Foundation

public struct ArtifactRevision: Sendable, Hashable, Codable, Identifiable {
    public let id: RevisionID
    public let artifactID: ArtifactID
    public let parentRevisionID: RevisionID?
    public let contentHash: ContentHash
    public let deviceID: DeviceID
    public let createdAt: Date
    public let retention: ArtifactRetention

    public init?(
        id: RevisionID,
        artifactID: ArtifactID,
        parentRevisionID: RevisionID?,
        contentHash: ContentHash,
        deviceID: DeviceID,
        createdAt: Date,
        retention: ArtifactRetention = .fullHistory
    ) {
        guard parentRevisionID != id else { return nil }

        self.id = id
        self.artifactID = artifactID
        self.parentRevisionID = parentRevisionID
        self.contentHash = contentHash
        self.deviceID = deviceID
        self.createdAt = createdAt
        self.retention = retention
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(RevisionID.self, forKey: .id)
        let decodedParentRevisionID = try container.decodeIfPresent(
            RevisionID.self, forKey: .parentRevisionID)

        guard decodedParentRevisionID != decodedID else {
            throw DecodingError.dataCorruptedError(
                forKey: .parentRevisionID,
                in: container,
                debugDescription: "Artifact revision is its own parent: \(decodedID)"
            )
        }

        id = decodedID
        parentRevisionID = decodedParentRevisionID
        artifactID = try container.decode(ArtifactID.self, forKey: .artifactID)
        contentHash = try container.decode(ContentHash.self, forKey: .contentHash)
        deviceID = try container.decode(DeviceID.self, forKey: .deviceID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        retention =
            try container.decodeIfPresent(ArtifactRetention.self, forKey: .retention)
            ?? .fullHistory
    }
}
