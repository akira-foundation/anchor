import Foundation
import Testing

@testable import AnchorProvider

@Suite("Workspace change observing contract")
struct WorkspaceChangeObservingContractTests {
    private let workspace = URL(filePath: "/Developer/payable")

    @Test("a change in a watched location is announced once")
    func aChangeInAWatchedLocationIsAnnouncedOnce() async throws {
        let observer = ScriptedWorkspaceChangeObserver(
            scriptedChanges: [
                WorkspaceChange(
                    workspaceURL: workspace, changedPaths: ["docs/superpowers/plans/00-indice.md"]
                )
            ]
        )

        var announced: [WorkspaceChange] = []
        for await change in observer.observeWorkspaceChanges(at: workspace) {
            announced.append(change)
        }

        #expect(announced.count == 1)
        #expect(announced.first?.changedPaths == ["docs/superpowers/plans/00-indice.md"])
    }

    @Test("a burst arrives as one announcement carrying every path")
    func aBurstArrivesAsOneAnnouncementCarryingEveryPath() async throws {
        let burst = Set((0..<101).map { "graphify-out/cache/entry-\($0).json" })
        let observer = ScriptedWorkspaceChangeObserver(
            scriptedChanges: [WorkspaceChange(workspaceURL: workspace, changedPaths: burst)]
        )

        var announced: [WorkspaceChange] = []
        for await change in observer.observeWorkspaceChanges(at: workspace) {
            announced.append(change)
        }

        #expect(announced.count == 1)
        #expect(announced.first?.changedPaths.count == 101)
    }

    @Test("stopping ends the stream rather than leaving it open")
    func stoppingEndsTheStreamRatherThanLeavingItOpen() async throws {
        let observer = ScriptedWorkspaceChangeObserver(scriptedChanges: [])

        var announced = 0
        for await _ in observer.observeWorkspaceChanges(at: workspace) { announced += 1 }
        await observer.stopObserving()

        #expect(announced == 0)
    }
}

private struct ScriptedWorkspaceChangeObserver: WorkspaceChangeObserving {
    let scriptedChanges: [WorkspaceChange]

    func observeWorkspaceChanges(at workspaceURL: URL) -> AsyncStream<WorkspaceChange> {
        AsyncStream { continuation in
            for change in scriptedChanges { continuation.yield(change) }
            continuation.finish()
        }
    }

    func stopObserving() async {}
}
