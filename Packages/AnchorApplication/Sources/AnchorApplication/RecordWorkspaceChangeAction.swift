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
    public let revisionID: RevisionID
    public let contentHash: ContentHash

    public init(artifact: Artifact, revisionID: RevisionID, contentHash: ContentHash) {
        self.artifact = artifact
        self.revisionID = revisionID
        self.contentHash = contentHash
    }
}

public enum RecordWorkspaceChangeOutcome: Sendable, Equatable {
    case recorded([RecordedArtifactRevision])
    case deviceCannotDiscover

    public var revisionCount: Int {
        switch self {
        case .recorded(let revisions): revisions.count
        case .deviceCannotDiscover: 0
        }
    }
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
                    revisionID: revision.id,
                    contentHash: revision.contentHash
                ))
        }

        return .recorded(recorded)
    }
}
