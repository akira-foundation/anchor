import CoreServices
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Observation startup", .serialized)
struct ObservationStartupTests {
    @Test("a startup loss callback joins every path before the first checkpoint")
    func startupLossIncludesTransientPathBeforeCheckpoint() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/startup.json": "before"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .zero, captureSnapshot: captures.capture,
            currentEventID: { 500 },
            registerStream: { stream in
                let registered = registerStoppedStream(stream)
                try! Data("after".utf8).write(
                    to: workspace.appending(path: "graphify-out/startup.json"))
                return registered
            })
        let changes = try await startObservation(
            using: observer, at: workspace,
            receiving: NativeFileSystemEventBatch(
                paths: [
                    workspace.path, workspace.appending(path: "graphify-out/transient.json").path,
                ],
                flags: [UInt32(kFSEventStreamEventFlagMustScanSubDirs), 0], eventIDs: [449, 450]))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        let first = await iterator.next()
        #expect(
            first?.change.changedPaths == [
                "graphify-out/startup.json", "graphify-out/transient.json",
            ])
        #expect(first?.checkpoint == 500)
        #expect(await iterator.next() == nil)
        #expect(captures.count == 2)
    }

    @Test("zero-delay native delivery cannot overtake startup recovery")
    func immediateNativeDeliveryWaitsForStartupRecovery() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/startup.json": "before"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .zero, captureSnapshot: captures.capture,
            currentEventID: { 100 },
            registerStream: { stream in
                let registered = registerStoppedStream(stream)
                try! Data("after".utf8).write(
                    to: workspace.appending(path: "graphify-out/startup.json"))
                return registered
            })
        let changes = try await observer.startCheckpointedWorkspaceObservation(at: workspace)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/later.json").path], flags: [0],
                eventIDs: [300]))

        var iterator = changes.makeAsyncIterator()
        let first = await iterator.next()
        await observer.stopObserving()
        #expect(first?.change.changedPaths.contains("graphify-out/startup.json") == true)
        #expect(first?.checkpoint == 100)
        #expect(captures.count == 2)
    }

    @Test("startup reconciles a registration-time write once with the pre-scan watermark")
    func startupReconcilesRegistrationWriteConservatively() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "before"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .seconds(10),
            captureSnapshot: captures.capture,
            currentEventID: captures.currentEventID,
            registerStream: { stream in
                try! Data("after".utf8).write(
                    to: workspace.appending(path: "graphify-out/graph.json"))
                return FSEventStreamStart(stream)
            })
        let changes = try await observer.startCheckpointedWorkspaceObservation(at: workspace)
        try await Task.sleep(for: .milliseconds(250))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        let announcement = await iterator.next()
        #expect(announcement?.change.changedPaths == ["graphify-out/graph.json"])
        #expect(announcement?.checkpoint == 100)
        #expect(await iterator.next() == nil)
        #expect(captures.count == 2)
    }

    @Test(
        "loss flags recover changes absent from the native paths",
        arguments: [
            UInt32(kFSEventStreamEventFlagMustScanSubDirs),
            UInt32(kFSEventStreamEventFlagUserDropped),
            UInt32(kFSEventStreamEventFlagKernelDropped),
        ])
    func lossFlagsReconcileMissingPaths(_ flag: UInt32) async throws {
        let workspace = try WorkspaceFixture.make([
            "graphify-out/graph.json": "before", "docs/superpowers/plans/removed.md": "old",
        ])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .seconds(10), captureSnapshot: captures.capture,
            currentEventID: captures.currentEventID)
        let changes = try await observer.startCheckpointedWorkspaceObservation(at: workspace)
        try await Task.sleep(for: .milliseconds(150))
        try Data("after!".utf8).write(to: workspace.appending(path: "graphify-out/graph.json"))
        try FileManager.default.removeItem(
            at: workspace.appending(path: "docs/superpowers/plans/removed.md"))
        try Data("new".utf8).write(to: workspace.appending(path: "graphify-out/new.json"))
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.path], flags: [flag], eventIDs: [900]))
        try await Task.sleep(for: .milliseconds(150))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        let announcement = await iterator.next()
        #expect(
            announcement?.change.changedPaths == [
                "graphify-out/graph.json", "graphify-out/new.json",
                "docs/superpowers/plans/removed.md",
            ])
        #expect(announcement?.checkpoint == 200)
        #expect(await iterator.next() == nil)
        #expect(captures.count == 3)
    }

    @Test("ordinary native events do not trigger scans and unchanged recovery emits nothing")
    func ordinaryEventsDoNotRescanAndUnchangedRecoveryDoesNotAdvance() async throws {
        let workspace = try WorkspaceFixture.make([:])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .milliseconds(20), captureSnapshot: captures.capture,
            currentEventID: captures.currentEventID)
        let changes = try await observer.startCheckpointedWorkspaceObservation(at: workspace)
        try await Task.sleep(for: .milliseconds(150))
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/graph.json").path],
                flags: [0], eventIDs: [50]))
        try await Task.sleep(for: .milliseconds(100))
        #expect(captures.count == 2)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.path], flags: [UInt32(kFSEventStreamEventFlagUserDropped)],
                eventIDs: [900]))
        try await Task.sleep(for: .milliseconds(150))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        let announcement = await iterator.next()
        #expect(announcement?.change.changedPaths == ["graphify-out/graph.json"])
        #expect(announcement?.checkpoint == 50)
        #expect(await iterator.next() == nil)
        #expect(captures.count == 3)
    }

    @Test("a write immediately after startup is observed")
    func immediateWriteIsObserved() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "before"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let observer = FileSystemEventObserver(silenceWindow: .milliseconds(20))
        let changes = try await observer.startWorkspaceObservation(at: workspace)
        try Data("after".utf8).write(to: workspace.appending(path: "graphify-out/graph.json"))
        let timeout = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await observer.stopObserving()
        }
        var iterator = changes.makeAsyncIterator()
        let change = await iterator.next()
        timeout.cancel()
        await observer.stopObserving()
        #expect(change?.changedPaths.contains("graphify-out/graph.json") == true)
    }

    @Test("an incomplete recovery scan emits no checkpoint")
    func incompleteRecoveryDoesNotAdvanceCheckpoint() async throws {
        let workspace = try WorkspaceFixture.make([
            "graphify-out/graph.json": "before", "graphify-out/unreadable.json": "secret",
        ])
        let unreadablePath = workspace.appending(path: "graphify-out/unreadable.json").path
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: unreadablePath)
            try? FileManager.default.removeItem(at: workspace)
        }
        let observer = FileSystemEventObserver(silenceWindow: .seconds(10))
        let changes = try await observer.startCheckpointedWorkspaceObservation(at: workspace)
        try await Task.sleep(for: .milliseconds(150))
        try Data("after".utf8).write(to: workspace.appending(path: "graphify-out/graph.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadablePath)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.path], flags: [UInt32(kFSEventStreamEventFlagUserDropped)],
                eventIDs: [900]))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }

    @Test("a loss batch preserves watched paths from the same native callback")
    func lossBatchPreservesNativePaths() async throws {
        let workspace = try WorkspaceFixture.make([:])
        let captures = SnapshotCaptures()
        let observer = FileSystemEventObserver(
            silenceWindow: .seconds(10), captureSnapshot: captures.capture,
            currentEventID: captures.currentEventID)
        let changes = try await observer.startCheckpointedWorkspaceObservation(at: workspace)
        try await Task.sleep(for: .milliseconds(150))
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [
                    workspace.path, workspace.appending(path: "graphify-out/transient.json").path,
                ],
                flags: [UInt32(kFSEventStreamEventFlagUserDropped), 0], eventIDs: [500, 501]))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        let announcement = await iterator.next()
        #expect(announcement?.change.changedPaths == ["graphify-out/transient.json"])
        #expect(announcement?.checkpoint == 200)
    }

    @Test("native registration failure is reported")
    func registrationFailureIsReported() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "before"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let observer = FileSystemEventObserver()
        #expect(throws: ObservationStartupFailure.self) {
            try FileSystemEventStream.start(
                at: workspace, resumingFrom: nil, observationID: UUID(), delivering: observer,
                register: { _ in false })
        }
    }
}
