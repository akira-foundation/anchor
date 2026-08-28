import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorStorage
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
        workspaceURL: URL
    ) -> (WorkspaceObservationCoordinator, StoredSyncOperationJournal) {
        let operationJournal = StoredSyncOperationJournal(storage: storage)
        let coordinator = WorkspaceObservationCoordinator(
            device: device,
            observer: FileSystemEventObserver(silenceWindow: .milliseconds(200)),
            checkpointStore: checkpointStore,
            operationJournal: operationJournal,
            recordChange: RecordWorkspaceChangeAction(
                discoverer: SuperpowersArtifactProvider(workspaceURL: workspaceURL),
                contentReader: WorkspaceFileContentReader(),
                revisionRecorder: ArtifactRevisionRecorder(
                    journal: StoredArtifactRevisionJournal(
                        storage: storage, contentStore: StoredArtifactContentStore(storage: storage)
                    ),
                    contentStore: StoredArtifactContentStore(storage: storage),
                    deviceID: device.id
                ),
                operationJournal: operationJournal
            )
        )

        return (coordinator, operationJournal)
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

        #expect(try await journal.currentState(of: interrupted.id) == .pending)
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

    @Test("an edit becomes a revision and a queued operation, and moves the checkpoint")
    func anEditBecomesARevisionAndAQueuedOperation() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "before"])
        let storage = InMemoryStorageProvider()
        let checkpointStore = ObservationCheckpointStore(fileURL: makeCheckpointURL())
        let mac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)
        let (coordinator, journal) = makeCoordinator(
            device: mac, storage: storage, checkpointStore: checkpointStore, workspaceURL: workspace
        )

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        try await Task.sleep(for: .milliseconds(400))
        try Data("after".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))
        let queued = await pendingCount(in: journal, reaching: 1, within: .seconds(10))
        await coordinator.stopObserving()

        #expect(queued == 1)
        #expect(try checkpointStore.checkpoint(forWorkspaceAt: workspace) != nil)
    }

    private func pendingCount(
        in journal: StoredSyncOperationJournal,
        reaching target: Int,
        within timeout: Duration
    ) async -> Int {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let count = (try? await journal.pendingOperations().count) ?? 0
            if count >= target { return count }
            try? await Task.sleep(for: .milliseconds(100))
        }

        return (try? await journal.pendingOperations().count) ?? 0
    }

    private func makeCheckpointURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-coordinator-\(UUID().uuidString)/checkpoints.json")
    }
}
