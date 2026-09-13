import AnchorDomain
import AnchorProvider
import CoreServices
import Foundation

@testable import AnchorPlatformMacOS

actor CheckpointDiscoveryGate: ArtifactDiscovering {
    struct Refusal: Error {}

    nonisolated let attempts: AsyncStream<Int>
    private let attemptContinuation: AsyncStream<Int>.Continuation
    private let discoverer: any ArtifactDiscovering
    private let pausedAttempts: Set<Int>
    private let refusedAttempts: Set<Int>
    private var attemptCount = 0
    private var waitingAttempts: [Int: CheckedContinuation<Void, Never>] = [:]

    init(
        discoverer: any ArtifactDiscovering,
        pausedAttempts: Set<Int> = [1, 2], refusedAttempts: Set<Int> = []
    ) {
        let channel = AsyncStream<Int>.makeStream()
        attempts = channel.stream
        attemptContinuation = channel.continuation
        self.discoverer = discoverer
        self.pausedAttempts = pausedAttempts
        self.refusedAttempts = refusedAttempts
    }

    func discoverArtifacts(forProject projectID: ProjectID) async throws -> [DiscoveredArtifact] {
        attemptCount += 1
        let attempt = attemptCount
        if pausedAttempts.contains(attempt) {
            await withCheckedContinuation { continuation in
                waitingAttempts[attempt] = continuation
                attemptContinuation.yield(attempt)
            }
        }
        guard !refusedAttempts.contains(attempt) else { throw Refusal() }
        return try await discoverer.discoverArtifacts(forProject: projectID)
    }

    func resumeAttempt(_ attempt: Int) {
        waitingAttempts.removeValue(forKey: attempt)?.resume()
    }
}

extension FileSystemEventObserver {
    func deliverCheckpointTestChange(at fileURL: URL, checkpoint: UInt64) {
        receiveEvents(
            NativeFileSystemEventBatch(
                paths: [fileURL.path, "/history-done"],
                flags: [0, UInt32(kFSEventStreamEventFlagHistoryDone)],
                eventIDs: [checkpoint, checkpoint]))
    }

    static func checkpointTestObserver() -> FileSystemEventObserver {
        FileSystemEventObserver(
            silenceWindow: .zero, captureSnapshot: WorkspaceFileSnapshot.capture,
            currentEventID: { 50 },
            registerStream: { stream in
                let registered = FSEventStreamStart(stream)
                if registered { FSEventStreamStop(stream) }
                return registered
            })
    }
}
