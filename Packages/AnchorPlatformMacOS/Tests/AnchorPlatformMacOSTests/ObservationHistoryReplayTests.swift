import CoreServices
import Foundation
import Testing

@testable import AnchorPlatformMacOS

extension ObservationStartupTests {
    @Test("lost offline deletion keeps the durable checkpoint poisoned after HistoryDone")
    func lostOfflineDeletionPoisonsCheckpoint() async throws {
        let workspace = try WorkspaceFixture.make([
            "graphify-out/deleted.json": "previously recorded"
        ])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let checkpointStore = ObservationCheckpointStore(
            fileURL: workspace.appending(path: "checkpoints.json"))
        try checkpointStore.recordCheckpoint(50, forWorkspaceAt: workspace)
        try FileManager.default.removeItem(
            at: workspace.appending(path: "graphify-out/deleted.json"))
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .zero, captureSnapshot: captures.capture,
            currentEventID: { 1_000 }, registerStream: registerStoppedStream)
        let changes = try await observer.startCheckpointedWorkspaceObservation(
            at: workspace, resumingFrom: checkpointStore.checkpoint(forWorkspaceAt: workspace))
        await captures.waitForCapture(2)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.path], flags: [UInt32(kFSEventStreamEventFlagMustScanSubDirs)],
                eventIDs: [100]))
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.path], flags: [UInt32(kFSEventStreamEventFlagHistoryDone)],
                eventIDs: [200]))
        var iterator = changes.makeAsyncIterator()
        for checkpoint: UInt64 in [300, 400] {
            await observer.receiveEvents(
                NativeFileSystemEventBatch(
                    paths: [workspace.appending(path: "graphify-out/later.json").path],
                    flags: [0], eventIDs: [checkpoint]))
            let announcement = try #require(await iterator.next())
            try checkpointStore.recordCheckpoint(announcement.checkpoint, forWorkspaceAt: workspace)
            #expect(try checkpointStore.checkpoint(forWorkspaceAt: workspace) == 50)
        }
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/transient.json").path],
                flags: [UInt32(kFSEventStreamEventFlagKernelDropped)], eventIDs: [500]))
        let recovery = try #require(await iterator.next())
        try checkpointStore.recordCheckpoint(recovery.checkpoint, forWorkspaceAt: workspace)
        await observer.stopObserving()
        #expect(try checkpointStore.checkpoint(forWorkspaceAt: workspace) == 50)
    }

    @Test("clean HistoryDone releases the resume cap without announcing its sentinel path")
    func historyDoneReleasesResumeCapWithoutAnnouncingSentinel() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "before"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .seconds(10), captureSnapshot: captures.capture,
            currentEventID: { 300 },
            registerStream: { stream in
                let registered = registerStoppedStream(stream)
                try! Data("after".utf8).write(
                    to: workspace.appending(path: "graphify-out/graph.json"))
                return registered
            })
        let changes = try await observer.startCheckpointedWorkspaceObservation(
            at: workspace, resumingFrom: 50)
        await captures.waitForCapture(2)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/ignored-sentinel.json").path],
                flags: [UInt32(kFSEventStreamEventFlagHistoryDone)], eventIDs: [250]))
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.path], flags: [UInt32(kFSEventStreamEventFlagKernelDropped)],
                eventIDs: [300]))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        let historicalRecovery = await iterator.next()
        let contemporaryRecovery = await iterator.next()
        #expect(historicalRecovery?.checkpoint == 50)
        #expect(contemporaryRecovery?.checkpoint == 300)
        #expect(contemporaryRecovery?.change.changedPaths == ["graphify-out/graph.json"])
        #expect(await iterator.next() == nil)
    }

    @Test("history loss recovers offline edits before a later native checkpoint")
    func historyLossRecoversOfflineEditsBeforeLaterCheckpoint() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/offline.json": "recorded"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        try Data("edited while stopped".utf8).write(
            to: workspace.appending(path: "graphify-out/offline.json"))
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .zero, captureSnapshot: captures.capture,
            currentEventID: captures.currentEventID, registerStream: registerStoppedStream)
        let changes = try await observer.startCheckpointedWorkspaceObservation(
            at: workspace, resumingFrom: 50)
        await captures.waitForCapture(2)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.path], flags: [UInt32(kFSEventStreamEventFlagMustScanSubDirs)],
                eventIDs: [100]))
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/later.json").path], flags: [0],
                eventIDs: [300]))

        var iterator = changes.makeAsyncIterator()
        let first = await iterator.next()
        await observer.stopObserving()
        #expect(first?.change.changedPaths.contains("graphify-out/offline.json") == true)
        #expect(first?.checkpoint == 50)
    }

    @Test("startup recovery does not skip historical events awaiting delivery")
    func startupRecoveryPreservesResumeCheckpoint() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "before"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .seconds(10), captureSnapshot: captures.capture,
            currentEventID: captures.currentEventID,
            registerStream: { stream in
                let registered = FSEventStreamStart(stream)
                if registered { FSEventStreamStop(stream) }
                try! Data("after".utf8).write(
                    to: workspace.appending(path: "graphify-out/graph.json"))
                return registered
            })
        let changes = try await observer.startCheckpointedWorkspaceObservation(
            at: workspace, resumingFrom: 50)
        try await Task.sleep(for: .milliseconds(150))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        let announcement = await iterator.next()
        #expect(announcement?.change.changedPaths == ["graphify-out/graph.json"])
        #expect(announcement?.checkpoint == 50)
    }
}
