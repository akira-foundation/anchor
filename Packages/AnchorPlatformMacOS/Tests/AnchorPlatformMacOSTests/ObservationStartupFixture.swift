import CoreServices
import Foundation
import Synchronization

@testable import AnchorPlatformMacOS

final class SnapshotCaptures: Sendable {
    private let captureCount = Mutex(0)
    private let captureEvents = AsyncStream<Int>.makeStream()

    var count: Int { captureCount.withLock { $0 } }

    func currentEventID() -> UInt64 { UInt64(count * 100) }

    func capture(at workspaceURL: URL) -> WorkspaceFileSnapshot {
        let snapshot = WorkspaceFileSnapshot.capture(at: workspaceURL)
        let completedCount = captureCount.withLock {
            $0 += 1
            return $0
        }
        captureEvents.continuation.yield(completedCount)
        return snapshot
    }

    func waitForCapture(_ requestedCount: Int) async {
        for await completedCount in captureEvents.stream {
            if completedCount >= requestedCount { return }
        }
    }
}

func registerStoppedStream(_ stream: FSEventStreamRef) -> Bool {
    let registered = FSEventStreamStart(stream)
    if registered { FSEventStreamStop(stream) }
    return registered
}

func startObservation(
    using observer: isolated FileSystemEventObserver, at workspaceURL: URL,
    receiving batch: NativeFileSystemEventBatch
) throws -> AsyncStream<CheckpointedWorkspaceChange> {
    let changes = try observer.startCheckpointedWorkspaceObservation(at: workspaceURL)
    observer.receiveEvents(batch)
    return changes
}

func startObservation(
    using observer: isolated FileSystemEventObserver, at workspaceURL: URL,
    receiving firstBatch: NativeFileSystemEventBatch,
    beforeSecondBatch: @Sendable () throws -> Void,
    receiving secondBatch: NativeFileSystemEventBatch
) throws -> AsyncStream<CheckpointedWorkspaceChange> {
    let changes = try observer.startCheckpointedWorkspaceObservation(at: workspaceURL)
    observer.receiveEvents(firstBatch)
    try beforeSecondBatch()
    observer.receiveEvents(secondBatch)
    return changes
}
