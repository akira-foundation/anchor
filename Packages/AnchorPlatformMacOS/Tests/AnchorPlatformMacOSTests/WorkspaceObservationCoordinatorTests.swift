import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorStorage
import AnchorSync
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Workspace observation coordinator", .serialized)
struct WorkspaceObservationCoordinatorTests {
    private let projectID = ProjectID()

    private func makeCoordinator(
        device: Device,
        storage: InMemoryStorageProvider,
        checkpointStore: ObservationCheckpointStore,
        workspaceURL: URL,
        remote: InMemoryStorageProvider = InMemoryStorageProvider()
    ) -> (WorkspaceObservationCoordinator, StoredSyncOperationJournal) {
        let operationJournal = StoredSyncOperationJournal(storage: storage)
        let coordinator = WorkspaceObservationCoordinator(
            device: device,
            observer: FileSystemEventObserver(silenceWindow: .milliseconds(200)),
            checkpointStore: checkpointStore,
            operationJournal: operationJournal,
            recordChange: RecordWorkspaceChangeAction(
                discoverer: CompositeArtifactDiscoverer([
                    SuperpowersArtifactProvider(workspaceURL: workspaceURL),
                    GraphifyArtifactProvider(workspaceURL: workspaceURL),
                    ClaudeSessionProvider(workspaceURL: workspaceURL),
                ]),
                contentReader: CompositeArtifactContentReader([
                    WorkspaceFileContentReader(),
                    ClaudeSessionContentReader(projectID: projectID),
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

    @Test("starting recovers an operation the last run left uploading")
    func startingRecoversAnOperationTheLastRunLeftUploading() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let storage = InMemoryStorageProvider()
        let mac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)
        let (coordinator, journal) = makeCoordinator(
            device: mac, storage: storage,
            checkpointStore: ObservationCheckpointStore(fileURL: makeCheckpointURL()),
            workspaceURL: workspace
        )
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: ArtifactID(), parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("x".utf8)),
                deviceID: mac.id, createdAt: Date(timeIntervalSince1970: 0)
            )
        )
        let interrupted = try await journal.queueOperation(
            for: revision, storageKey: try #require(StorageKey(rawValue: "projects/x"))
        )
        try await journal.recordTransition(of: interrupted.id, to: .uploading)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        await coordinator.stopObserving()

        #expect(try await journal.history(of: interrupted.id).map(\.state).contains(.pending))
    }

    @Test("starting announces this machine on the project")
    func startingAnnouncesThisMachineOnTheProject() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let storage = InMemoryStorageProvider()
        let remote = InMemoryStorageProvider()
        let mac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)
        let (coordinator, _) = makeCoordinator(
            device: mac, storage: storage,
            checkpointStore: ObservationCheckpointStore(fileURL: makeCheckpointURL()),
            workspaceURL: workspace, remote: remote
        )

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        await coordinator.stopObserving()

        let announced = try await StoredDevicePresenceRegistry(storage: remote)
            .presences(onProject: projectID)

        #expect(announced.map(\.deviceID) == [mac.id])
        #expect(announced.first?.lastSeenAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test("a device that cannot discover never starts observing")
    func aDeviceThatCannotDiscoverNeverStartsObserving() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let storage = InMemoryStorageProvider()
        let phone = Device(id: DeviceID(), displayName: "iPhone", platform: .iOS)
        let (coordinator, journal) = makeCoordinator(
            device: phone, storage: storage,
            checkpointStore: ObservationCheckpointStore(fileURL: makeCheckpointURL()),
            workspaceURL: workspace
        )
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: ArtifactID(), parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("x".utf8)),
                deviceID: phone.id, createdAt: Date(timeIntervalSince1970: 0)
            )
        )
        let interrupted = try await journal.queueOperation(
            for: revision, storageKey: try #require(StorageKey(rawValue: "projects/x"))
        )
        try await journal.recordTransition(of: interrupted.id, to: .uploading)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        await coordinator.stopObserving()

        #expect(try await journal.currentState(of: interrupted.id) == .uploading)
    }

    @Test("an edit reaches the other side, and moves the checkpoint")
    func anEditReachesTheOtherSideAndMovesTheCheckpoint() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "before"])
        let storage = InMemoryStorageProvider()
        let remote = InMemoryStorageProvider()
        let checkpointStore = ObservationCheckpointStore(fileURL: makeCheckpointURL())
        let mac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)
        let (coordinator, _) = makeCoordinator(
            device: mac, storage: storage, checkpointStore: checkpointStore,
            workspaceURL: workspace, remote: remote
        )

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        try await Task.sleep(for: .milliseconds(400))
        try Data("after".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))
        let published = await publishedRevisionCount(
            in: remote, reaching: 1, within: .seconds(10))
        await coordinator.stopObserving()

        #expect(published == 1)
        #expect(try checkpointStore.checkpoint(forWorkspaceAt: workspace) != nil)
    }

    private func publishedRevisionCount(
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

    private func makeCheckpointURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-coordinator-\(UUID().uuidString)/checkpoints.json")
    }
}
