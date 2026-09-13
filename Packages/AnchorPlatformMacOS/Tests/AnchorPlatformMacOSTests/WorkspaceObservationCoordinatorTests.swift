import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorStorage
import AnchorSync
import CoreServices
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Workspace observation coordinator", .serialized)
struct WorkspaceObservationCoordinatorTests {
    let projectID = ProjectID()

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

    @Test("an incomplete recovery clears observation state and permits restart")
    func incompleteRecoveryClearsStateAndPermitsRestart() async throws {
        let workspace = try WorkspaceFixture.make([
            "graphify-out/graph.json": "before", "graphify-out/unreadable.json": "secret",
        ])
        let unreadablePath = workspace.appending(path: "graphify-out/unreadable.json").path
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: unreadablePath)
            try? FileManager.default.removeItem(at: workspace)
        }
        let observer = FileSystemEventObserver(
            silenceWindow: .zero, captureSnapshot: WorkspaceFileSnapshot.capture,
            currentEventID: { 100 },
            registerStream: { stream in
                let registered = FSEventStreamStart(stream)
                if registered { FSEventStreamStop(stream) }
                return registered
            })
        let remote = InMemoryStorageProvider()
        let (coordinator, _) = makeCoordinator(
            device: Device(id: DeviceID(), displayName: "Studio", platform: .macOS),
            storage: InMemoryStorageProvider(),
            checkpointStore: ObservationCheckpointStore(fileURL: makeCheckpointURL()),
            workspaceURL: workspace, remote: remote, observer: observer,
            discoverer: GraphifyArtifactProvider(workspaceURL: workspace))
        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadablePath)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.path], flags: [UInt32(kFSEventStreamEventFlagUserDropped)],
                eventIDs: [100]))

        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await coordinator.isObserving, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await coordinator.isObserving == false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: unreadablePath)
        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        try Data("after restart".utf8).write(
            to: workspace.appending(path: "graphify-out/graph.json"))
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/graph.json").path], flags: [0],
                eventIDs: [200]))
        let published = await publishedRevisionCount(in: remote, reaching: 1, within: .seconds(1))
        #expect(await coordinator.recordedRefusals == [])
        #expect(await coordinator.isObserving)
        await coordinator.stopObserving()
        #expect(published == 1)
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
        try Data("after".utf8)
            .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))
        let published = await publishedRevisionCount(
            in: remote, reaching: 1, within: .seconds(10))
        await coordinator.stopObserving()

        #expect(published == 1)
        #expect(try checkpointStore.checkpoint(forWorkspaceAt: workspace) != nil)
    }

    @Test("stopping a coordinator that never started is not a failure")
    func stoppingCoordinatorThatNeverStartedIsNotAFailure() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let mac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)
        let (coordinator, _) = makeCoordinator(
            device: mac, storage: InMemoryStorageProvider(),
            checkpointStore: ObservationCheckpointStore(fileURL: makeCheckpointURL()),
            workspaceURL: workspace)

        await coordinator.stopObserving()

        #expect(await coordinator.isObserving == false)
    }

    @Test("starting a coordinator that is already observing does not start a second observation")
    func startingCoordinatorAlreadyObservingDoesNotStartSecondObservation() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let mac = Device(id: DeviceID(), displayName: "Studio", platform: .macOS)
        let (coordinator, _) = makeCoordinator(
            device: mac, storage: InMemoryStorageProvider(),
            checkpointStore: ObservationCheckpointStore(fileURL: makeCheckpointURL()),
            workspaceURL: workspace)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)
        await coordinator.stopObserving()

        #expect(await coordinator.isObserving == false)
    }

    @Test("a device that cannot discover locally never begins observing")
    func deviceThatCannotDiscoverLocallyNeverBeginsObserving() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let phone = Device(id: DeviceID(), displayName: "Phone", platform: .iOS)
        let (coordinator, _) = makeCoordinator(
            device: phone, storage: InMemoryStorageProvider(),
            checkpointStore: ObservationCheckpointStore(fileURL: makeCheckpointURL()),
            workspaceURL: workspace)

        try await coordinator.startObserving(workspaceAt: workspace, forProject: projectID)

        #expect(await coordinator.isObserving == false)
    }

}
