import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorStorage
import AnchorSync
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("What a coordinator remembers about what it could not do", .serialized)
struct CoordinatorRefusalTests {
    let projectID = ProjectID()

    @Test("a stopped startup can be restarted immediately")
    func stoppedStartupCanRestartImmediately() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "{}"])
        let coordinator = makeCoordinator(
            discoverer: CompositeArtifactDiscoverer([]),
            synchronizer: DeferredArtifactSynchronizer(), checkpointURL: checkpointURL())
        for _ in 0..<20 {
            let starting = Task {
                try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
            }
            while !(await coordinator.isObserving) { await Task.yield() }
            await coordinator.stopObserving()
            try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
            #expect(await coordinator.isObserving)
            try await starting.value
            await coordinator.stopObserving()
        }
    }

    @Test("concurrent starts initialize the coordinator only once")
    func concurrentStartsInitializeOnlyOnce() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "{}"])
        let coordinator = makeCoordinator(
            discoverer: CompositeArtifactDiscoverer([]),
            synchronizer: RefusingSynchronizer(), checkpointURL: checkpointURL())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await coordinator.startObserving(
                        workspaceAt: workspace, forProject: projectID)
                }
            }
            try await group.waitForAll()
        }
        await coordinator.stopObserving()
        #expect(await coordinator.recordedRefusalCount == 1)
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

    @Test("refusals found before observation are reported once")
    func refusalsFoundBeforeObservationAreReportedOnce() async {
        let coordinator = makeCoordinator(
            discoverer: CompositeArtifactDiscoverer([]),
            synchronizer: DeferredArtifactSynchronizer(),
            checkpointURL: checkpointURL(),
            initialRefusals: ["indexing session: model unavailable"]
        )

        #expect(await coordinator.recordedRefusals == ["indexing session: model unavailable"])
        #expect(await coordinator.recordedRefusals == ["indexing session: model unavailable"])
        #expect(await coordinator.recordedRefusalCount == 1)

        await coordinator.recordRefusals(["indexing session: model became unavailable again"])

        #expect(await coordinator.recordedRefusalCount == 2)
        #expect(await coordinator.recordedRefusals.count == 2)
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
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: checkpoints.deletingLastPathComponent())
        }

        let observer = FileSystemEventObserver.checkpointTestObserver()
        let synchronizer = SuspendedStartupSynchronizer()
        var startup = synchronizer.started.makeAsyncIterator()
        let coordinator = makeCoordinator(
            discoverer: RefusingDiscoverer(),
            synchronizer: synchronizer,
            checkpointURL: checkpoints, observer: observer
        )

        async let starting: Void = coordinator.startObserving(
            workspaceAt: workspace, forProject: projectID)

        #expect(await startup.next() == true)
        let planURL = workspace.appending(path: "docs/superpowers/plans/00-indice.md")
        try Data("revised while starting".utf8).write(to: planURL)
        await observer.deliverCheckpointTestChange(at: planURL, checkpoint: 100)

        let refusals = await waitForRefusal(from: coordinator)
        #expect(refusals.contains { $0.hasPrefix("recording the change:") })
        await synchronizer.finishStartup()
        try await starting
        await coordinator.stopObserving()
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
