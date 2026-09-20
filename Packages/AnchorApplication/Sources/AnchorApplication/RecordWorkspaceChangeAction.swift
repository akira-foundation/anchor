import AnchorDomain
import AnchorProvider
import Foundation

public struct RecordWorkspaceChangeRequest: Sendable, Equatable {
    public let device: Device
    public let projectID: ProjectID
    public let change: WorkspaceChange

    public init(device: Device, projectID: ProjectID, change: WorkspaceChange) {
        self.device = device
        self.projectID = projectID
        self.change = change
    }
}

public struct RecordedArtifactRevision: Sendable, Equatable {
    public let artifact: Artifact
    public let revision: ArtifactRevision

    public var revisionID: RevisionID { revision.id }
    public var contentHash: ContentHash { revision.contentHash }

    public init(artifact: Artifact, revision: ArtifactRevision) {
        self.artifact = artifact
        self.revision = revision
    }
}

public enum RecordWorkspaceChangeOutcome: Sendable, Equatable {
    case recorded([RecordedArtifactRevision])
    case deviceCannotDiscover
}

public struct RecordWorkspaceChangeAction: Action {
    private let discoverer: any ArtifactDiscovering
    private let contentReader: any ArtifactContentReading
    private let revisionRecorder: ArtifactRevisionRecorder
    private let operationJournal: any SyncOperationJournal

    public init(
        discoverer: any ArtifactDiscovering,
        contentReader: any ArtifactContentReading,
        revisionRecorder: ArtifactRevisionRecorder,
        operationJournal: any SyncOperationJournal
    ) {
        self.discoverer = discoverer
        self.contentReader = contentReader
        self.revisionRecorder = revisionRecorder
        self.operationJournal = operationJournal
    }

    public func perform(
        _ request: RecordWorkspaceChangeRequest
    ) async throws -> RecordWorkspaceChangeOutcome {
        guard request.device.canDiscoverLocalProviders else { return .deviceCannotDiscover }

        var recorded: [RecordedArtifactRevision] = []
        for discovered in try await discoverer.discoverArtifacts(forProject: request.projectID) {
            let revision = try await revisionRecorder.recordRevision(
                of: discovered.artifact,
                contentHash: discovered.contentHash
            ) {
                try await contentReader.readContent(
                    ofArtifactNamed: discovered.artifact.name,
                    inWorkspaceAt: request.change.workspaceURL
                )
            }
            guard let revision, let storageKey = StorageKey(rawValue: discovered.artifact.name)
            else {
                continue
            }

            _ = try await operationJournal.queueOperation(for: revision, storageKey: storageKey)
            recorded.append(
                RecordedArtifactRevision(
                    artifact: discovered.artifact,
                    revision: revision
                ))
        }

        return .recorded(recorded)
    }
}
