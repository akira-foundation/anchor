import AnchorApplication
import AnchorDomain
import AnchorProvider
import AnchorStorage
import AnchorSync
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct RefusingDiscoverer: ArtifactDiscovering {
    struct Refusal: Error {}

    func discoverArtifacts(forProject projectID: ProjectID) async throws -> [DiscoveredArtifact] {
        throw Refusal()
    }
}

struct RefusingSynchronizer: ArtifactRevisionSynchronizing {
    struct Refusal: Error {}

    func synchronizePendingArtifactRevisions() async throws { throw Refusal() }
}

actor SuspendedStartupSynchronizer: ArtifactRevisionSynchronizing {
    nonisolated let started: AsyncStream<Bool>
    private let startContinuation: AsyncStream<Bool>.Continuation
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false

    init() {
        let channel = AsyncStream<Bool>.makeStream()
        started = channel.stream
        startContinuation = channel.continuation
    }

    func synchronizePendingArtifactRevisions() async throws {
        guard !didStart else { return }
        didStart = true
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
            startContinuation.yield(true)
        }
    }

    func finishStartup() {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

extension CoordinatorRefusalTests {
    func makeCoordinator(
        discoverer: any ArtifactDiscovering,
        synchronizer: any ArtifactRevisionSynchronizing,
        checkpointURL: URL,
        initialRefusals: [String] = [],
        observer: FileSystemEventObserver = FileSystemEventObserver(
            silenceWindow: .milliseconds(100))
    ) -> WorkspaceObservationCoordinator {
        let storage = InMemoryStorageProvider()
        let contentStore = StoredArtifactContentStore(storage: storage)
        let operationJournal = StoredSyncOperationJournal(storage: storage)

        return WorkspaceObservationCoordinator(
            device: Device(id: DeviceID(), displayName: "Studio", platform: .macOS),
            observer: observer,
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
            presences: DeferredDevicePresenceRegistry(),
            initialRefusals: initialRefusals
        )
    }

    func checkpointURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-refusals-\(UUID().uuidString)/checkpoints.json")
    }

    func waitForRefusal(from coordinator: WorkspaceObservationCoordinator) async -> [String] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))

        while ContinuousClock.now < deadline {
            let refusals = await coordinator.recordedRefusals

            guard refusals.isEmpty else { return refusals }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return []
    }

}
