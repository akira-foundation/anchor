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
        content: Data
    ) async throws -> ArtifactRevision? {
        let contentHash = ContentHash.digest(of: content)
        let latestRevision = try await journal.latestRevision(forArtifact: artifact.id)
        guard latestRevision?.contentHash != contentHash else { return nil }

        let revision = ArtifactRevision(
            id: RevisionID(),
            artifactID: artifact.id,
            parentRevisionID: parentRevisionID(after: latestRevision, under: artifact.retention),
            contentHash: contentHash,
            deviceID: deviceID,
            createdAt: Date()
        )
        guard let revision else { return nil }

        try await contentStore.storeContent(content, forRevision: revision.id)
        try await journal.recordRevision(revision)

        return revision
    }

    private func parentRevisionID(
        after latestRevision: ArtifactRevision?,
        under retention: ArtifactRetention
    ) -> RevisionID? {
        switch retention {
        case .fullHistory: latestRevision?.id
        case .latestRevisionOnly: nil
        }
    }
}
