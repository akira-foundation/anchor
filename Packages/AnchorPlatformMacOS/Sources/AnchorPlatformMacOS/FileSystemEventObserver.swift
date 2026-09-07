import AnchorProvider
import CoreServices
import Foundation

struct CheckpointedWorkspaceChange: Sendable {
    let change: WorkspaceChange
    let checkpoint: UInt64
}

public actor FileSystemEventObserver: WorkspaceChangeObserving {
    public static let defaultSilenceWindow = Duration.milliseconds(300)

    private let silenceWindow: Duration
    private let captureSnapshot: @Sendable (URL) -> WorkspaceFileSnapshot
    private let currentEventID: @Sendable () -> UInt64
    private let registerStream: @Sendable (FSEventStreamRef) -> Bool
    private var stream: FSEventStreamRef?
    private var observationID: UUID?
    private var continuation: AsyncStream<CheckpointedWorkspaceChange>.Continuation?
    private var pendingPaths: Set<String> = []
    private var pendingCheckpoint: UInt64?
    private var flushTask: Task<Void, Never>?
    private var startupReconciliationTask: Task<Void, Never>?
    private var startupReconciliationPending = false
    private var snapshot: WorkspaceFileSnapshot?
    private var resumeCheckpointLimit: UInt64?
    private var historicalReplayLostEvents = false
    private var workspaceURL: URL?

    public init(silenceWindow: Duration = FileSystemEventObserver.defaultSilenceWindow) {
        self.silenceWindow = silenceWindow
        captureSnapshot = WorkspaceFileSnapshot.capture
        currentEventID = { FSEventsGetCurrentEventId() }
        registerStream = { FSEventStreamStart($0) }
    }

    init(
        silenceWindow: Duration,
        captureSnapshot: @escaping @Sendable (URL) -> WorkspaceFileSnapshot,
        currentEventID: @escaping @Sendable () -> UInt64,
        registerStream: @escaping @Sendable (FSEventStreamRef) -> Bool = { FSEventStreamStart($0) }
    ) {
        self.silenceWindow = silenceWindow
        self.captureSnapshot = captureSnapshot
        self.currentEventID = currentEventID
        self.registerStream = registerStream
    }

    nonisolated public func observeWorkspaceChanges(
        at workspaceURL: URL
    ) -> AsyncStream<WorkspaceChange> {
        observeWorkspaceChanges(at: workspaceURL, resumingFrom: nil)
    }

    nonisolated public func observeWorkspaceChanges(
        at workspaceURL: URL,
        resumingFrom checkpoint: UInt64?
    ) -> AsyncStream<WorkspaceChange> {
        AsyncStream { continuation in
            let observationTask = Task {
                do {
                    let changes = try await self.startCheckpointedWorkspaceObservation(
                        at: workspaceURL, resumingFrom: checkpoint)
                    for await announcement in changes {
                        continuation.yield(announcement.change)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in observationTask.cancel() }
        }
    }

    public func latestCheckpoint() -> UInt64? {
        stream.map(FileSystemEventStream.latestEventID)
    }

    func startWorkspaceObservation(
        at workspaceURL: URL, resumingFrom checkpoint: UInt64? = nil
    ) throws -> AsyncStream<WorkspaceChange> {
        let changes = try startCheckpointedWorkspaceObservation(
            at: workspaceURL, resumingFrom: checkpoint)
        return AsyncStream { continuation in
            let forwardingTask = Task {
                for await announcement in changes { continuation.yield(announcement.change) }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwardingTask.cancel() }
        }
    }

    func startCheckpointedWorkspaceObservation(
        at workspaceURL: URL, resumingFrom checkpoint: UInt64? = nil,
        observationID: UUID = UUID()
    ) throws -> AsyncStream<CheckpointedWorkspaceChange> {
        let channel = AsyncStream<CheckpointedWorkspaceChange>.makeStream()
        try startObserving(
            at: workspaceURL, resumingFrom: checkpoint,
            observationID: observationID, continuation: channel.continuation)
        return channel.stream
    }

    public func stopObserving() async {
        finishObservation()
    }

    func stopObserving(forObservation observationID: UUID) {
        guard self.observationID == observationID else { return }
        finishObservation()
    }

    private func finishObservation() {
        flushTask?.cancel()
        flushTask = nil
        startupReconciliationTask?.cancel()
        startupReconciliationTask = nil
        startupReconciliationPending = false
        snapshot = nil
        resumeCheckpointLimit = nil
        historicalReplayLostEvents = false
        stream.map(FileSystemEventStream.tearDown)
        stream = nil
        observationID = nil
        continuation?.finish()
        continuation = nil
        pendingPaths.removeAll()
        pendingCheckpoint = nil
        workspaceURL = nil
    }

    func receiveEvents(_ batch: NativeFileSystemEventBatch) {
        guard let observationID else { return }
        receiveEvents(batch, forObservation: observationID)
    }

    func receiveEvents(_ batch: NativeFileSystemEventBatch, forObservation observationID: UUID) {
        guard self.observationID == observationID, let workspaceURL else { return }

        let historyDoneFlag = UInt32(kFSEventStreamEventFlagHistoryDone)
        let pathIndices = batch.paths.indices.filter { batch.flags[$0] & historyDoneFlag == 0 }
        let relativePaths = pathIndices.compactMap {
            WorkspacePath.relativePath(of: batch.paths[$0], under: workspaceURL)
        }
        let watched = relativePaths.filter(WorkspacePath.isWatched)
        let reconciliationFlags = UInt32(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)
        let requiresReconciliation = batch.flags.contains { $0 & reconciliationFlags != 0 }
        if requiresReconciliation {
            if resumeCheckpointLimit != nil { historicalReplayLostEvents = true }
            reconcileSnapshot(including: Set(watched), recoveringLostEvents: true)
        }
        if !requiresReconciliation, !watched.isEmpty,
            let checkpoint = pathIndices.map({ batch.eventIDs[$0] }).max()
        {
            pendingPaths.formUnion(watched)
            pendingCheckpoint = max(pendingCheckpoint ?? checkpoint, checkpoint)
            scheduleFlush()
        }

        if batch.flags.contains(where: { $0 & historyDoneFlag != 0 }) {
            flush()
            if !historicalReplayLostEvents { resumeCheckpointLimit = nil }
        }
    }

    private func startObserving(
        at workspaceURL: URL,
        resumingFrom checkpoint: UInt64?,
        observationID: UUID,
        continuation: AsyncStream<CheckpointedWorkspaceChange>.Continuation
    ) throws {
        let baseline = captureSnapshot(workspaceURL)
        guard baseline.isComplete else { throw WorkspaceFileSnapshot.CaptureFailure.incomplete }
        let startedStream = try FileSystemEventStream.start(
            at: workspaceURL, resumingFrom: checkpoint, observationID: observationID,
            delivering: self, register: registerStream
        )
        self.workspaceURL = workspaceURL
        self.continuation = continuation
        stream = startedStream
        self.observationID = observationID
        snapshot = baseline
        resumeCheckpointLimit = checkpoint
        historicalReplayLostEvents = false
        startupReconciliationPending = true
        startupReconciliationTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            self.completeStartupReconciliation()
            self.startupReconciliationTask = nil
        }
    }

    private func completeStartupReconciliation() {
        guard startupReconciliationPending else { return }
        reconcileSnapshot()
    }

    private func reconcileSnapshot(
        including nativePaths: Set<String> = [], recoveringLostEvents: Bool = false
    ) {
        guard let workspaceURL, let snapshot else { return }
        startupReconciliationPending = false
        let watermark = currentEventID()
        let refreshedSnapshot = captureSnapshot(workspaceURL)
        guard refreshedSnapshot.isComplete else {
            finishObservation()
            return
        }
        let recoveredPaths =
            recoveringLostEvents
            ? refreshedSnapshot.knownPaths.union(snapshot.knownPaths)
            : refreshedSnapshot.changedPaths(since: snapshot)
        let changedPaths = recoveredPaths.union(nativePaths)
        self.snapshot = refreshedSnapshot
        guard !changedPaths.isEmpty else { return }

        continuation?.yield(
            CheckpointedWorkspaceChange(
                change: WorkspaceChange(
                    workspaceURL: workspaceURL, changedPaths: changedPaths.union(pendingPaths)),
                checkpoint: min(watermark, resumeCheckpointLimit ?? watermark)))
        flushTask?.cancel()
        flushTask = nil
        pendingPaths.removeAll()
        pendingCheckpoint = nil
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [silenceWindow] in
            try? await Task.sleep(for: silenceWindow)
            guard !Task.isCancelled else { return }
            self.flush()
        }
    }

    private func flush() {
        completeStartupReconciliation()
        guard let workspaceURL, let pendingCheckpoint, !pendingPaths.isEmpty else { return }

        let deliveredCheckpoint =
            historicalReplayLostEvents
            ? min(pendingCheckpoint, resumeCheckpointLimit ?? pendingCheckpoint)
            : pendingCheckpoint
        continuation?.yield(
            CheckpointedWorkspaceChange(
                change: WorkspaceChange(workspaceURL: workspaceURL, changedPaths: pendingPaths),
                checkpoint: deliveredCheckpoint)
        )
        pendingPaths.removeAll()
        self.pendingCheckpoint = nil
    }
}
