import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorStorage
import AnchorSync
import Foundation
import Testing

@testable import AnchorPlatformMacOS

extension WorkspaceObservationCoordinatorTests {
    @Test("a recorded batch persists its own checkpoint while a later batch is buffered")
    func recordedBatchPersistsItsOwnCheckpoint() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "{}"])
        let checkpointURL = makeCheckpointURL()
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: checkpointURL.deletingLastPathComponent())
        }
        let checkpointStore = ObservationCheckpointStore(fileURL: checkpointURL)
        try checkpointStore.recordCheckpoint(50, forWorkspaceAt: workspace)
        let observer = FileSystemEventObserver.checkpointTestObserver()
        let discovery = CheckpointDiscoveryGate(
            discoverer: GraphifyArtifactProvider(workspaceURL: workspace), refusedAttempts: [2])
        var attempts = discovery.attempts.makeAsyncIterator()
        let remote = InMemoryStorageProvider()
        let (coordinator, _) = makeCoordinator(
            device: Device(id: DeviceID(), displayName: "Studio", platform: .macOS),
            storage: InMemoryStorageProvider(), checkpointStore: checkpointStore,
            workspaceURL: workspace, remote: remote, observer: observer, discoverer: discovery)
        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        let graphURL = workspace.appending(path: "graphify-out/graph.json")
        await observer.deliverCheckpointTestChange(at: graphURL, checkpoint: 100)
        #expect(await attempts.next() == 1)
        await observer.deliverCheckpointTestChange(at: graphURL, checkpoint: 200)
        #expect(try checkpointStore.checkpoint(forWorkspaceAt: workspace) == 50)
        await discovery.resumeAttempt(1)
        #expect(await attempts.next() == 2)

        #expect(try checkpointStore.checkpoint(forWorkspaceAt: workspace) == 100)
        #expect(
            try await StoredRevisionFeed(storage: remote).revisions(after: nil).revisions.count == 1
        )
        await discovery.resumeAttempt(2)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await coordinator.isObserving, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try checkpointStore.checkpoint(forWorkspaceAt: workspace) == 100)
        await coordinator.stopObserving()
    }

}

extension CoordinatorRefusalTests {
    @Test("a refused first batch stops before a buffered later batch can advance its checkpoint")
    func refusedFirstBatchStopsBeforeBufferedCheckpoint() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "{}"])
        let checkpoints = checkpointURL()
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: checkpoints.deletingLastPathComponent())
        }
        let store = ObservationCheckpointStore(fileURL: checkpoints)
        try store.recordCheckpoint(50, forWorkspaceAt: workspace)
        let observer = FileSystemEventObserver.checkpointTestObserver()
        let discovery = CheckpointDiscoveryGate(
            discoverer: GraphifyArtifactProvider(workspaceURL: workspace),
            pausedAttempts: [1], refusedAttempts: [1])
        var attempts = discovery.attempts.makeAsyncIterator()
        let coordinator = makeCoordinator(
            discoverer: discovery, synchronizer: DeferredArtifactSynchronizer(),
            checkpointURL: checkpoints, observer: observer)
        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        let graphURL = workspace.appending(path: "graphify-out/graph.json")
        await observer.deliverCheckpointTestChange(at: graphURL, checkpoint: 100)
        #expect(await attempts.next() == 1)
        await observer.deliverCheckpointTestChange(at: graphURL, checkpoint: 200)
        await discovery.resumeAttempt(1)

        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await coordinator.isObserving, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await coordinator.isObserving == false)
        #expect(
            await coordinator.recordedRefusals.contains { $0.hasPrefix("recording the change:") })
        #expect(try store.checkpoint(forWorkspaceAt: workspace) == 50)
        await coordinator.stopObserving()
    }

}
