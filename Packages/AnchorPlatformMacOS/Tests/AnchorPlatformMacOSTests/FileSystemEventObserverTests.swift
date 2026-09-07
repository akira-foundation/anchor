import AnchorProvider
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("File system event observer", .serialized)
struct FileSystemEventObserverTests {
    @Test("a buffered change retains its batch checkpoint after newer events arrive")
    func bufferedChangeRetainsItsBatchCheckpoint() async throws {
        let workspace = try WorkspaceFixture.make([:])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let observer = FileSystemEventObserver(silenceWindow: .milliseconds(20))
        let changes = try await observer.startCheckpointedWorkspaceObservation(at: workspace)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/first.json").path],
                flags: [0], eventIDs: [101]))
        try await Task.sleep(for: .milliseconds(100))
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/second.json").path],
                flags: [0], eventIDs: [202]))
        try await Task.sleep(for: .milliseconds(100))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(first?.change.changedPaths == ["graphify-out/first.json"])
        #expect(first?.checkpoint == 101)
        #expect(second?.change.changedPaths == ["graphify-out/second.json"])
        #expect(second?.checkpoint == 202)
        #expect(await iterator.next() == nil)
    }

    @Test("coalesced paths retain the maximum native event ID")
    func coalescedPathsRetainMaximumNativeEventID() async throws {
        let workspace = try WorkspaceFixture.make([:])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let observer = FileSystemEventObserver(silenceWindow: .milliseconds(20))
        let changes = try await observer.startCheckpointedWorkspaceObservation(at: workspace)
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: ["graphify-out/first.json", "graphify-out/second.json"].map {
                    workspace.appending(path: $0).path
                }, flags: [0, 0], eventIDs: [505, 202]))
        await observer.receiveEvents(
            NativeFileSystemEventBatch(
                paths: [workspace.appending(path: "graphify-out/third.json").path],
                flags: [0], eventIDs: [404]))
        try await Task.sleep(for: .milliseconds(100))
        await observer.stopObserving()

        var iterator = changes.makeAsyncIterator()
        let announcement = await iterator.next()
        #expect(
            announcement?.change.changedPaths == [
                "graphify-out/first.json", "graphify-out/second.json", "graphify-out/third.json",
            ])
        #expect(announcement?.checkpoint == 505)
        #expect(await iterator.next() == nil)
    }

    private func firstChange(
        in workspace: URL,
        after write: @escaping @Sendable () throws -> Void
    ) async throws -> WorkspaceChange? {
        let observer = FileSystemEventObserver(silenceWindow: .milliseconds(200))
        let changes = try await observer.startWorkspaceObservation(at: workspace)
        try write()

        let announced = await withTaskGroup(of: WorkspaceChange?.self) { group in
            group.addTask {
                for await change in changes { return change }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                await observer.stopObserving()
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        await observer.stopObserving()

        return announced
    }

    @Test("a change in a watched location is announced with its relative path")
    func aChangeInAWatchedLocationIsAnnouncedWithItsRelativePath() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "before"])

        let change = try await firstChange(in: workspace) {
            try Data("after".utf8).write(
                to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))
        }

        #expect(change?.changedPaths.contains("docs/superpowers/plans/00-indice.md") == true)
    }

    @Test("a burst of writes is aggregated rather than announced file by file")
    func aBurstOfWritesIsAggregatedRatherThanAnnouncedFileByFile() async throws {
        let workspace = try WorkspaceFixture.make(["graphify-out/graph.json": "{}"])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let observer = FileSystemEventObserver(silenceWindow: .milliseconds(250))
        let changes = try await observer.startWorkspaceObservation(at: workspace)
        for index in 0..<50 {
            try Data("burst \(index)".utf8)
                .write(to: workspace.appending(path: "graphify-out/file-\(index).json"))
        }

        let collector = Task {
            var announcements: [Set<String>] = []
            for await change in changes { announcements.append(change.changedPaths) }
            return announcements
        }
        try await Task.sleep(for: .seconds(2))
        await observer.stopObserving()
        let announcements = await collector.value

        #expect(announcements.count < 5)
        let expectedPaths = Set((0..<50).map { "graphify-out/file-\($0).json" })
        #expect(
            announcements.reduce(into: Set<String>()) { $0.formUnion($1) }.isSuperset(
                of: expectedPaths))
    }

    @Test("a change outside the watched locations is never announced")
    func aChangeOutsideTheWatchedLocationsIsNeverAnnounced() async throws {
        let workspace = try WorkspaceFixture.make(["node_modules/pkg/index.js": "before"])

        let change = try await firstChange(in: workspace) {
            try Data("after".utf8).write(to: workspace.appending(path: "node_modules/pkg/index.js"))
        }

        #expect(change == nil)
    }
}

@Suite("Workspace path filter")
struct WorkspacePathTests {
    @Test(
        "every location the two providers write to is watched",
        arguments: [
            "docs/superpowers/plans/00-indice.md",
            "Docs/superpowers/specs/01-scaffold.md",
            ".superpowers/brainstorm/idea.md",
            ".superpowers/sdd/design-review.md",
            "graphify-out/graph.json",
        ]
    )
    func everyProviderLocationIsWatched(_ relativePath: String) {
        #expect(WorkspacePath.isWatched(relativePath))
    }

    @Test(
        "nothing else is watched",
        arguments: [
            "README.md", "node_modules/pkg/index.js", ".build/debug/thing.o",
            "docs/architecture.md",
        ]
    )
    func nothingElseIsWatched(_ relativePath: String) {
        #expect(!WorkspacePath.isWatched(relativePath))
    }

    @Test("a path outside the workspace has no relative form")
    func aPathOutsideTheWorkspaceHasNoRelativeForm() {
        let workspace = URL(filePath: "/Developer/payable")

        #expect(WorkspacePath.relativePath(of: "/Developer/other/file.md", under: workspace) == nil)
        #expect(
            WorkspacePath.relativePath(of: "/Developer/payable/docs/a.md", under: workspace)
                == "docs/a.md"
        )
    }
}
