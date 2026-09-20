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
    private let sessionContext: SessionContextRecording?
    private let artifactIndex: (any ArtifactContextIndexing)?
    private let contextStatus: ContextReadModelStatusStore?
    private let now: @Sendable () -> Date
    private var observationTask: Task<Void, Never>?
    private var activeObservationID: UUID?
    private var isStartingObservation = false
    private var startupWasCancelled = false
    private var startupWaiters: [CheckedContinuation<Void, Never>] = []
    private var refusals: [String] = []
    private var refusalCount = 0

    public init(
        device: Device,
        observer: FileSystemEventObserver,
        checkpointStore: ObservationCheckpointStore,
        operationJournal: any SyncOperationJournal,
        recordChange: RecordWorkspaceChangeAction,
        synchronizer: any ArtifactRevisionSynchronizing,
        presences: any DevicePresenceRegistry,
        sessionContext: SessionContextRecording? = nil,
        artifactIndex: (any ArtifactContextIndexing)? = nil,
        contextStatus: ContextReadModelStatusStore? = nil,
        initialRefusals: [String] = [],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.device = device
        self.observer = observer
        self.checkpointStore = checkpointStore
        self.operationJournal = operationJournal
        self.recordChange = recordChange
        self.synchronizer = synchronizer
        self.presences = presences
        self.sessionContext = sessionContext
        self.artifactIndex = artifactIndex
        self.contextStatus = contextStatus
        refusals = Array(initialRefusals.suffix(Self.rememberedRefusalCount))
        refusalCount = initialRefusals.count
        self.now = now
    }

    public var isObserving: Bool {
        observationTask != nil || (isStartingObservation && !startupWasCancelled)
    }

    public var recordedRefusals: [String] { refusals }

    public var recordedRefusalCount: Int { refusalCount }

    public func recordRefusals(_ descriptions: [String]) {
        refusalCount += descriptions.count
        refusals.append(contentsOf: descriptions)
        refusals = Array(refusals.suffix(Self.rememberedRefusalCount))
    }

    public func startObserving(
        workspaceAt workspaceURL: URL, forProject projectID: ProjectID
    ) async throws {
        guard device.canDiscoverLocalProviders, !isObserving, !isStartingObservation else { return }
        isStartingObservation = true
        startupWasCancelled = false
        let observationID = UUID()
        activeObservationID = observationID
        let changes: AsyncStream<CheckpointedWorkspaceChange>
        do {
            let checkpoint = try checkpointStore.checkpoint(forWorkspaceAt: workspaceURL)
            changes = try await observer.startCheckpointedWorkspaceObservation(
                at: workspaceURL, resumingFrom: checkpoint, observationID: observationID)
        } catch {
            activeObservationID = nil
            finishObservationStartup()
            throw error
        }
        guard !startupWasCancelled else {
            await observer.stopObserving(forObservation: observationID)
            finishObservationStartup()
            return
        }
        finishObservationStartup()

        observationTask = Task { [weak self] in
            for await announcement in changes {
                guard let self,
                    await self.recordObservedChange(
                        announcement, forProject: projectID, observationID: observationID)
                else { break }
            }
            await self?.finishObservationStream(observationID)
        }

        await recording("recovering interrupted operations") {
            try await operationJournal.recoverInterruptedOperations()
        }
        await recording("announcing presence") { try await announcePresence(onProject: projectID) }
        await recording("synchronizing revisions") {
            try await synchronizer.synchronizePendingArtifactRevisions()
        }
    }

    public func stopObserving() async {
        let observationID = activeObservationID
        startupWasCancelled = true
        observationTask?.cancel()
        observationTask = nil
        activeObservationID = nil
        if let observationID { await observer.stopObserving(forObservation: observationID) }
        if isStartingObservation {
            await withCheckedContinuation { startupWaiters.append($0) }
        }
    }

    private func finishObservationStream(_ observationID: UUID) async {
        guard activeObservationID == observationID else { return }
        await observer.stopObserving(forObservation: observationID)
        guard activeObservationID == observationID else { return }
        activeObservationID = nil
        observationTask = nil
    }

    private func finishObservationStartup() {
        isStartingObservation = false
        let waitingStops = startupWaiters
        startupWaiters.removeAll()
        for waitingStop in waitingStops { waitingStop.resume() }
    }

    private func announcePresence(onProject projectID: ProjectID) async throws {
        try await presences.announcePresence(
            DevicePresence(projectID: projectID, deviceID: device.id, lastSeenAt: now())
        )
    }

    private func recordObservedChange(
        _ announcement: CheckpointedWorkspaceChange,
        forProject projectID: ProjectID, observationID: UUID
    ) async -> Bool {
        guard activeObservationID == observationID, !Task.isCancelled else { return false }
        let change = announcement.change
        var contextUpdate: ContextReadModelStatusStore.Update?
        guard
            await recording(
                "marking context unavailable",
                {
                    contextUpdate = try await contextStatus?.beginUpdate()
                })
        else { return false }
        var outcome: RecordWorkspaceChangeOutcome = .deviceCannotDiscover
        let recorded = await recording("recording the change") {
            outcome = try await recordChange.perform(
                RecordWorkspaceChangeRequest(device: device, projectID: projectID, change: change)
            )
        }

        guard recorded, case .recorded(let revisions) = outcome,
            activeObservationID == observationID, !Task.isCancelled
        else {
            await completeContextUpdate(contextUpdate, succeeded: false)
            return false
        }
        let artifactsIndexed = await recording("indexing artifact context") {
            try await artifactIndex?.indexArtifactRevisions(revisions)
        }
        let contextRefusals =
            await sessionContext?.recordSessionContext(in: revisions, at: now()) ?? []
        guard activeObservationID == observationID, !Task.isCancelled else {
            await completeContextUpdate(contextUpdate, succeeded: false)
            return false
        }
        for refusal in contextRefusals {
            remember("indexing \(refusal.artifactName)", refusal.description)
        }
        await completeContextUpdate(
            contextUpdate, succeeded: artifactsIndexed && contextRefusals.isEmpty)

        await recording("recording the checkpoint") {
            try checkpointStore.recordCheckpoint(
                announcement.checkpoint, forWorkspaceAt: change.workspaceURL)
        }

        await recording("announcing presence") { try await announcePresence(onProject: projectID) }
        await recording("synchronizing revisions") {
            try await synchronizer.synchronizePendingArtifactRevisions()
        }
        return activeObservationID == observationID && !Task.isCancelled
    }

    private func remember(_ attempt: String, _ description: String) {
        refusalCount += 1
        refusals.append("\(attempt): \(description)")
        refusals = refusals.suffix(Self.rememberedRefusalCount)
    }

    private func completeContextUpdate(
        _ update: ContextReadModelStatusStore.Update?, succeeded: Bool
    ) async {
        guard let update else { return }
        await recording("updating context availability") {
            try await contextStatus?.completeUpdate(update, succeeded: succeeded)
        }
    }

    @discardableResult
    private func recording(
        _ attempt: String, _ work: () async throws -> Void
    ) async -> Bool {
        do {
            try await work()

            return true
        } catch {
            remember(attempt, "\(error)")

            return false
        }
    }
}
