import AnchorDomain
import Foundation

public struct ArtifactRevisionRecorder: Sendable {
    private let journal: any ArtifactRevisionJournal
    private let contentStore: any ArtifactContentStore
    private let deviceID: DeviceID

    public init(
        journal: any ArtifactRevisionJournal,
        contentStore: any ArtifactContentStore,
        deviceID: DeviceID
    ) {
        self.journal = journal
        self.contentStore = contentStore
        self.deviceID = deviceID
    }

    public func recordRevision(
        of artifact: Artifact,
        contentHash: ContentHash,
        readingContent: () async throws -> Data?
    ) async throws -> ArtifactRevision? {
        let latestRevision = try await journal.latestRevision(forArtifact: artifact.id)
        guard latestRevision?.contentHash != contentHash else { return nil }
        guard let content = try await readingContent(),
            ContentHash.digest(of: content) == contentHash
        else { return nil }

        let revision = ArtifactRevision(
            id: RevisionID(),
            artifactID: artifact.id,
            parentRevisionID: latestRevision?.id,
            contentHash: contentHash,
            deviceID: deviceID,
            createdAt: Date(),
            retention: artifact.retention
        )
        guard let revision else { return nil }

        try await contentStore.storeContent(content, forRevision: revision.id)
        try await journal.recordRevision(revision)

        return revision
    }
}
