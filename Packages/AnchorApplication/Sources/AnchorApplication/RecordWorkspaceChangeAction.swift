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

public enum RecordWorkspaceChangeOutcome: Sendable, Equatable {
    case recorded(revisionCount: Int)
    case deviceCannotDiscover
}

public struct RecordWorkspaceChangeAction: Action {
    private let discoverer: any ArtifactDiscovering
    private let contentReader: any ArtifactContentReading
    private let revisionRecorder: ArtifactRevisionRecorder
    private let operationJournal: AppendOnlySyncOperationJournal

    public init(
        discoverer: any ArtifactDiscovering,
        contentReader: any ArtifactContentReading,
        revisionRecorder: ArtifactRevisionRecorder,
        operationJournal: AppendOnlySyncOperationJournal
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

        var recordedCount = 0
        for discovered in try await changedArtifacts(in: request) {
            let content = try await contentReader.readContent(
                ofArtifactNamed: discovered.artifact.name,
                inWorkspaceAt: request.change.workspaceURL
            )
            guard let content else { continue }

            let revision = try await revisionRecorder.recordRevision(
                of: discovered.artifact, content: content
            )
            guard let revision, let storageKey = StorageKey(rawValue: discovered.artifact.name)
            else {
                continue
            }

            _ = try await operationJournal.queueOperation(for: revision, storageKey: storageKey)
            recordedCount += 1
        }

        return .recorded(revisionCount: recordedCount)
    }

    private func changedArtifacts(
        in request: RecordWorkspaceChangeRequest
    ) async throws -> [DiscoveredArtifact] {
        try await discoverer.discoverArtifacts(forProject: request.projectID)
            .filter { request.change.changedPaths.contains($0.artifact.name) }
    }
}
