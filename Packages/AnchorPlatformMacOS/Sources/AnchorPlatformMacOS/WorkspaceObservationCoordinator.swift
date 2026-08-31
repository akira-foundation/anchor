import AnchorApplication
import AnchorDomain
import AnchorProvider
import Foundation

public actor WorkspaceObservationCoordinator {
    private static let rememberedRefusalCount = 20

    private let device: Device
    private let observer: FileSystemEventObserver
    private let checkpointStore: ObservationCheckpointStore
    private let operationJournal: any SyncOperationJournal
    private let recordChange: RecordWorkspaceChangeAction
    private let synchronizer: any ArtifactRevisionSynchronizing
    private let presences: any DevicePresenceRegistry
    private let now: @Sendable () -> Date
    private var observationTask: Task<Void, Never>?
    private var refusals: [String] = []

    public init(
        device: Device,
        observer: FileSystemEventObserver,
        checkpointStore: ObservationCheckpointStore,
        operationJournal: any SyncOperationJournal,
        recordChange: RecordWorkspaceChangeAction,
        synchronizer: any ArtifactRevisionSynchronizing,
        presences: any DevicePresenceRegistry,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.device = device
        self.observer = observer
        self.checkpointStore = checkpointStore
        self.operationJournal = operationJournal
        self.recordChange = recordChange
        self.synchronizer = synchronizer
        self.presences = presences
        self.now = now
    }

    public var isObserving: Bool { observationTask != nil }

    public var recordedRefusals: [String] { refusals }

    public func startObserving(
        workspaceAt workspaceURL: URL, forProject projectID: ProjectID
    ) async throws {
        guard device.canDiscoverLocalProviders, !isObserving else { return }

        try await operationJournal.recoverInterruptedOperations()
        try? await announcePresence(onProject: projectID)
        try? await synchronizer.synchronizePendingArtifactRevisions()

        let checkpoint = try checkpointStore.checkpoint(forWorkspaceAt: workspaceURL)
        let changes = observer.observeWorkspaceChanges(at: workspaceURL, resumingFrom: checkpoint)

        observationTask = Task { [weak self] in
            for await change in changes {
                await self?.handle(change, forProject: projectID)
            }
        }
    }

    public func stopObserving() async {
        observationTask?.cancel()
        observationTask = nil
        await observer.stopObserving()
    }

    private func announcePresence(onProject projectID: ProjectID) async throws {
        try await presences.announcePresence(
            DevicePresence(projectID: projectID, deviceID: device.id, lastSeenAt: now())
        )
    }

    private func handle(_ change: WorkspaceChange, forProject projectID: ProjectID) async {
        await recording("recording the change") {
            _ = try await recordChange.perform(
                RecordWorkspaceChangeRequest(device: device, projectID: projectID, change: change)
            )
        }

        await recording("announcing presence") { try await announcePresence(onProject: projectID) }
        await recording("synchronizing revisions") {
            try await synchronizer.synchronizePendingArtifactRevisions()
        }

        guard let reached = await observer.latestCheckpoint() else { return }

        await recording("recording the checkpoint") {
            try checkpointStore.recordCheckpoint(reached, forWorkspaceAt: change.workspaceURL)
        }
    }

    private func recording(
        _ attempt: String, _ work: () async throws -> Void
    ) async {
        do {
            try await work()
        } catch {
            refusals.append("\(attempt): \(error)")
            refusals = refusals.suffix(Self.rememberedRefusalCount)
        }
    }
}
