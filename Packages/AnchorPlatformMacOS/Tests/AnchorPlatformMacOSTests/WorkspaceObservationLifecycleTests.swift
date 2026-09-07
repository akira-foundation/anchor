import CoreServices
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Workspace observation generation lifecycle", .serialized)
struct WorkspaceObservationLifecycleTests {
    @Test("a delayed old delivery cannot change replacement paths or its resume cap")
    func delayedOldDeliveryPreservesReplacementObservation() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "{}"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let observer = FileSystemEventObserver(
            silenceWindow: .seconds(10), captureSnapshot: WorkspaceFileSnapshot.capture,
            currentEventID: { 1_000 }, registerStream: registerStoppedStream)
        let oldObservationID = UUID()
        let replacementObservationID = UUID()
        let oldChanges = try await observer.startCheckpointedWorkspaceObservation(
            at: workspace, observationID: oldObservationID)
        let oldBatch = NativeFileSystemEventBatch(
            paths: [workspace.appending(path: "graphify-out/stale.json").path, workspace.path],
            flags: [0, UInt32(kFSEventStreamEventFlagHistoryDone)], eventIDs: [200, 200])
        let deliveryGate = AsyncStream<CheckedContinuation<Void, Never>>.makeStream()
        let delayedDelivery = Task {
            guard !Task.isCancelled else { return }
            await withCheckedContinuation { deliveryGate.continuation.yield($0) }
            await observer.receiveEvents(oldBatch, forObservation: oldObservationID)
        }
        var gateIterator = deliveryGate.stream.makeAsyncIterator()
        let releaseDelivery = try #require(await gateIterator.next())
        await observer.stopObserving(forObservation: oldObservationID)
        delayedDelivery.cancel()
        let replacementChanges = try await observer.startCheckpointedWorkspaceObservation(
            at: workspace, resumingFrom: 50, observationID: replacementObservationID)
        releaseDelivery.resume()
        await delayedDelivery.value
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.path], flags: [UInt32(kFSEventStreamEventFlagKernelDropped)],
                eventIDs: [300]), forObservation: replacementObservationID)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/later.json").path, workspace.path],
                flags: [0, UInt32(kFSEventStreamEventFlagHistoryDone)], eventIDs: [400, 400]),
            forObservation: replacementObservationID)
        await observer.stopObserving(forObservation: replacementObservationID)

        var oldIterator = oldChanges.makeAsyncIterator()
        var replacementIterator = replacementChanges.makeAsyncIterator()
        #expect(await oldIterator.next() == nil)
        let recovery = await replacementIterator.next()
        #expect(recovery?.checkpoint == 50)
        #expect(recovery?.change.changedPaths == ["graphify-out/graph.json"])
        let laterChange = await replacementIterator.next()
        #expect(laterChange?.checkpoint == 50)
        #expect(laterChange?.change.changedPaths == ["graphify-out/later.json"])
        #expect(await replacementIterator.next() == nil)
    }

    @Test("a delayed old teardown cannot stop a replacement observation")
    func delayedOldTeardownPreservesReplacementObservation() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "{}"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let observer = FileSystemEventObserver.checkpointTestObserver()
        let oldObservationID = UUID()
        let replacementObservationID = UUID()
        let oldChanges = try await observer.startCheckpointedWorkspaceObservation(
            at: workspace, observationID: oldObservationID)
        await observer.stopObserving(forObservation: oldObservationID)
        let replacementChanges = try await observer.startCheckpointedWorkspaceObservation(
            at: workspace, observationID: replacementObservationID)

        await observer.stopObserving(forObservation: oldObservationID)
        await observer.deliverCheckpointTestChange(
            at: workspace.appending(path: "graphify-out/graph.json"), checkpoint: 200)
        await observer.stopObserving(forObservation: replacementObservationID)

        var oldIterator = oldChanges.makeAsyncIterator()
        var replacementIterator = replacementChanges.makeAsyncIterator()
        #expect(await oldIterator.next() == nil)
        let announcement = await replacementIterator.next()
        #expect(announcement?.checkpoint == 200)
        #expect(announcement?.change.changedPaths == ["graphify-out/graph.json"])
        #expect(await replacementIterator.next() == nil)
    }
}
