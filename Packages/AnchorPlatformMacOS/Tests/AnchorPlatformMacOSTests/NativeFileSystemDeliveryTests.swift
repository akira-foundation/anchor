import CoreServices
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Native file delivery", .serialized)
struct NativeFileSystemDeliveryTests {
    @Test("a burst after startup reconciliation arrives through native delivery")
    func burstAfterStartupReconciliationIsDelivered() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "{}"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let captures = AsyncStream<Void>.makeStream()
        let observer = FileSystemEventObserver(
            silenceWindow: .milliseconds(250),
            captureSnapshot: { workspaceURL in
                let snapshot = WorkspaceFileSnapshot.capture(at: workspaceURL)
                captures.continuation.yield(())
                return snapshot
            },
            currentEventID: { FSEventsGetCurrentEventId() })
        let changes = try await observer.startCheckpointedWorkspaceObservation(at: workspace)
        var captureIterator = captures.stream.makeAsyncIterator()
        await captureIterator.next()
        await captureIterator.next()

        let expectedPaths = Set((0..<50).map { "graphify-out/file-\($0).json" })
        for path in expectedPaths {
            try Data(path.utf8).write(to: workspace.appending(path: path))
        }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await observer.stopObserving()
        }
        var announcedPaths: Set<String> = []
        for await announcement in changes {
            announcedPaths.formUnion(announcement.change.changedPaths)
            if announcedPaths.isSuperset(of: expectedPaths) { break }
        }
        deadline.cancel()
        await observer.stopObserving()

        #expect(announcedPaths.isSuperset(of: expectedPaths))
    }
}
