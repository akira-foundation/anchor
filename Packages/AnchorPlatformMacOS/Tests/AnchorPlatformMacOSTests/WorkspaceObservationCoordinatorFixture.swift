import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorStorage
import AnchorSync
import Foundation
import Testing

@testable import AnchorPlatformMacOS

extension WorkspaceObservationCoordinatorTests {
    func makeCoordinator(
        device: Device,
        storage: InMemoryStorageProvider,
        checkpointStore: ObservationCheckpointStore,
        workspaceURL: URL,
        remote: InMemoryStorageProvider = InMemoryStorageProvider(),
        observer: FileSystemEventObserver = FileSystemEventObserver(
            silenceWindow: .milliseconds(200)),
        discoverer: (any ArtifactDiscovering)? = nil,
        artifactIndex: (any ArtifactContextIndexing)? = nil,
        contextStatus: ContextReadModelStatusStore? = nil,
        sessionContext: (any SessionContextRecording)? = nil
    ) -> (WorkspaceObservationCoordinator, StoredSyncOperationJournal) {
        let operationJournal = StoredSyncOperationJournal(storage: storage)
        let coordinator = WorkspaceObservationCoordinator(
            device: device,
            observer: observer,
            checkpointStore: checkpointStore,
            operationJournal: operationJournal,
            recordChange: RecordWorkspaceChangeAction(
                discoverer: discoverer
                    ?? CompositeArtifactDiscoverer([
                        SuperpowersArtifactProvider(workspaceURL: workspaceURL),
                        GraphifyArtifactProvider(workspaceURL: workspaceURL),
                        ClaudeSessionProvider(workspaceURL: workspaceURL),
                        CodexSessionProvider(workspaceURL: workspaceURL),
                    ]),
                contentReader: CompositeArtifactContentReader([
                    WorkspaceFileContentReader(),
                    ClaudeSessionContentReader(projectID: projectID),
                    CodexSessionContentReader(projectID: projectID),
                ]),
                revisionRecorder: ArtifactRevisionRecorder(
                    journal: StoredArtifactRevisionJournal(
                        storage: storage, contentStore: StoredArtifactContentStore(storage: storage)
                    ),
                    contentStore: StoredArtifactContentStore(storage: storage),
                    deviceID: device.id
                ),
                operationJournal: operationJournal
            ),
            synchronizer: makeSynchronizer(
                storage: storage, remote: remote, operations: operationJournal),
            presences: StoredDevicePresenceRegistry(storage: remote),
            sessionContext: sessionContext,
            artifactIndex: artifactIndex,
            contextStatus: contextStatus,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        return (coordinator, operationJournal)
    }

    private func makeSynchronizer(
        storage: InMemoryStorageProvider,
        remote: InMemoryStorageProvider,
        operations: StoredSyncOperationJournal
    ) -> ArtifactSynchronizer {
        ArtifactSynchronizer(
            local: makeRevisionStore(over: storage),
            remote: makeRevisionStore(over: remote),
            operations: operations,
            failures: StorageFailureClassifier(),
            feed: StoredRevisionFeed(storage: remote),
            cursors: StoredSyncCursorStore(storage: storage),
            divergences: StoredArtifactDivergenceJournal(storage: storage)
        )
    }

    private func makeRevisionStore(over storage: InMemoryStorageProvider) -> RevisionStore {
        RevisionStore(
            journal: StoredArtifactRevisionJournal(
                storage: storage, contentStore: StoredArtifactContentStore(storage: storage)),
            contents: StoredArtifactContentStore(storage: storage)
        )
    }

    func publishedRevisionCount(
        in remote: InMemoryStorageProvider,
        reaching target: Int,
        within limit: Duration
    ) async -> Int {
        let feed = StoredRevisionFeed(storage: remote)
        let deadline = ContinuousClock.now.advanced(by: limit)
        var seen = 0

        while ContinuousClock.now < deadline {
            seen = (try? await feed.revisions(after: nil).revisions.count) ?? 0

            guard seen < target else { return seen }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return seen
    }

    func makeCheckpointURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-coordinator-\(UUID().uuidString)/checkpoints.json")
    }
}
