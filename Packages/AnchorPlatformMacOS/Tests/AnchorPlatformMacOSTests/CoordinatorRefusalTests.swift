import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorStorage
import AnchorSync
import Foundation
import Testing

@testable import AnchorPlatformMacOS

private struct RefusingDiscoverer: ArtifactDiscovering {
    struct Refusal: Error {}

    func discoverArtifacts(forProject projectID: ProjectID) async throws -> [DiscoveredArtifact] {
        throw Refusal()
    }
}

private struct RefusingSynchronizer: ArtifactRevisionSynchronizing {
    struct Refusal: Error {}

    func synchronizePendingArtifactRevisions() async throws { throw Refusal() }
}

private struct SlowSynchronizer: ArtifactRevisionSynchronizing {
    func synchronizePendingArtifactRevisions() async throws {
        try await Task.sleep(for: .seconds(2))
    }
}

@Suite("What a coordinator remembers about what it could not do", .serialized)
struct CoordinatorRefusalTests {
    private let projectID = ProjectID()

    private func makeCoordinator(
        discoverer: any ArtifactDiscovering,
        synchronizer: any ArtifactRevisionSynchronizing,
        checkpointURL: URL
    ) -> WorkspaceObservationCoordinator {
        let storage = InMemoryStorageProvider()
        let contentStore = StoredArtifactContentStore(storage: storage)
        let operationJournal = StoredSyncOperationJournal(storage: storage)

        return WorkspaceObservationCoordinator(
            device: Device(id: DeviceID(), displayName: "Studio", platform: .macOS),
            observer: FileSystemEventObserver(silenceWindow: .milliseconds(100)),
            checkpointStore: ObservationCheckpointStore(fileURL: checkpointURL),
            operationJournal: operationJournal,
            recordChange: RecordWorkspaceChangeAction(
                discoverer: discoverer,
                contentReader: CompositeArtifactContentReader([WorkspaceFileContentReader()]),
                revisionRecorder: ArtifactRevisionRecorder(
                    journal: StoredArtifactRevisionJournal(
                        storage: storage, contentStore: contentStore),
                    contentStore: contentStore,
                    deviceID: DeviceID()
                ),
                operationJournal: operationJournal
            ),
            synchronizer: synchronizer,
            presences: DeferredDevicePresenceRegistry()
        )
    }

    private func checkpointURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-refusals-\(UUID().uuidString)/checkpoints.json")
    }

    private func waitForRefusal(from coordinator: WorkspaceObservationCoordinator) async -> [String]
    {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))

        while ContinuousClock.now < deadline {
            let refusals = await coordinator.recordedRefusals

            guard refusals.isEmpty else { return refusals }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return []
    }

    @Test("a refusal at start-up is remembered rather than swallowed")
    func refusalAtStartUpIsRememberedRatherThanSwallowed() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let checkpoints = checkpointURL()
        defer { try? FileManager.default.removeItem(at: checkpoints.deletingLastPathComponent()) }

        let coordinator = makeCoordinator(
            discoverer: CompositeArtifactDiscoverer([]),
            synchronizer: RefusingSynchronizer(),
            checkpointURL: checkpoints
        )

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        defer { Task { await coordinator.stopObserving() } }

        let refusals = await coordinator.recordedRefusals

        #expect(refusals.count == 1)
        #expect(refusals.first?.hasPrefix("synchronizing revisions:") == true)
    }

    @Test("a change that could not be recorded is remembered with the attempt that failed")
    func changeThatCouldNotBeRecordedIsRememberedWithAttemptThatFailed() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let checkpoints = checkpointURL()
        defer { try? FileManager.default.removeItem(at: checkpoints.deletingLastPathComponent()) }

        let coordinator = makeCoordinator(
            discoverer: RefusingDiscoverer(),
            synchronizer: DeferredArtifactSynchronizer(),
            checkpointURL: checkpoints
        )

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        defer { Task { await coordinator.stopObserving() } }

        try await Task.sleep(for: .milliseconds(400))
        try Data("revised".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))

        let refusals = await waitForRefusal(from: coordinator)

        #expect(refusals.contains { $0.hasPrefix("recording the change:") })
    }

    @Test("a change that could not be recorded does not move the checkpoint past it")
    func changeThatCouldNotBeRecordedDoesNotMoveCheckpointPastIt() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let checkpoints = checkpointURL()
        defer { try? FileManager.default.removeItem(at: checkpoints.deletingLastPathComponent()) }

        let coordinator = makeCoordinator(
            discoverer: RefusingDiscoverer(),
            synchronizer: DeferredArtifactSynchronizer(),
            checkpointURL: checkpoints
        )

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        defer { Task { await coordinator.stopObserving() } }

        try await Task.sleep(for: .milliseconds(400))
        try Data("revised".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))
        _ = await waitForRefusal(from: coordinator)

        #expect(
            try ObservationCheckpointStore(fileURL: checkpoints)
                .checkpoint(forWorkspaceAt: workspace) == nil)
    }

    @Test("a change that was recorded moves the checkpoint even when it could not travel")
    func changeThatWasRecordedMovesCheckpointEvenWhenItCouldNotTravel() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let checkpoints = checkpointURL()
        defer { try? FileManager.default.removeItem(at: checkpoints.deletingLastPathComponent()) }

        let coordinator = makeCoordinator(
            discoverer: CompositeArtifactDiscoverer([
                SuperpowersArtifactProvider(workspaceURL: workspace)
            ]),
            synchronizer: RefusingSynchronizer(),
            checkpointURL: checkpoints
        )

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        defer { Task { await coordinator.stopObserving() } }

        try await Task.sleep(for: .milliseconds(400))
        try Data("revised".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))

        let store = ObservationCheckpointStore(fileURL: checkpoints)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var reached: UInt64?

        while ContinuousClock.now < deadline, reached == nil {
            reached = try store.checkpoint(forWorkspaceAt: workspace)
            try? await Task.sleep(for: .milliseconds(50))
        }

        #expect(reached != nil)
        #expect(await coordinator.recordedRefusals.contains { $0.hasPrefix("synchronizing") })
    }

    @Test("a change made while the engine is still starting up is not lost")
    func changeMadeWhileEngineIsStillStartingUpIsNotLost() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let checkpoints = checkpointURL()
        defer { try? FileManager.default.removeItem(at: checkpoints.deletingLastPathComponent()) }

        let coordinator = makeCoordinator(
            discoverer: RefusingDiscoverer(),
            synchronizer: SlowSynchronizer(),
            checkpointURL: checkpoints
        )

        async let starting: Void = coordinator.startObserving(
            workspaceAt: workspace, forProject: projectID)

        try await Task.sleep(for: .milliseconds(400))
        try Data("revised while starting".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))

        try await starting
        defer { Task { await coordinator.stopObserving() } }

        let refusals = await waitForRefusal(from: coordinator)

        #expect(refusals.contains { $0.hasPrefix("recording the change:") })
    }

    @Test("the number of refusals is counted even once the oldest are forgotten")
    func numberOfRefusalsIsCountedEvenOnceOldestAreForgotten() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let checkpoints = checkpointURL()
        defer { try? FileManager.default.removeItem(at: checkpoints.deletingLastPathComponent()) }

        let coordinator = makeCoordinator(
            discoverer: CompositeArtifactDiscoverer([]),
            synchronizer: RefusingSynchronizer(),
            checkpointURL: checkpoints
        )

        for _ in 1...3 {
            try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
            await coordinator.stopObserving()
        }

        #expect(await coordinator.recordedRefusalCount == 3)
        #expect(await coordinator.recordedRefusals.count == 3)
    }
}
