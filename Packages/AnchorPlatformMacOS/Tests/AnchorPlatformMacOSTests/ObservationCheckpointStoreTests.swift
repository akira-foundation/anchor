import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Observation checkpoint store")
struct ObservationCheckpointStoreTests {
    private func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-checkpoints-\(UUID().uuidString)/checkpoints.json")
    }

    @Test("a workspace never observed has no checkpoint")
    func aWorkspaceNeverObservedHasNoCheckpoint() throws {
        let store = ObservationCheckpointStore(fileURL: makeStoreURL())

        #expect(try store.checkpoint(forWorkspaceAt: URL(filePath: "/Developer/payable")) == nil)
    }

    @Test("a checkpoint survives a new store over the same file")
    func aCheckpointSurvivesANewStoreOverTheSameFile() throws {
        let fileURL = makeStoreURL()
        let workspace = URL(filePath: "/Developer/payable")

        try ObservationCheckpointStore(fileURL: fileURL)
            .recordCheckpoint(382_417_622, forWorkspaceAt: workspace)

        let reopened = ObservationCheckpointStore(fileURL: fileURL)
        #expect(try reopened.checkpoint(forWorkspaceAt: workspace) == 382_417_622)
    }

    @Test("each workspace keeps its own checkpoint")
    func eachWorkspaceKeepsItsOwnCheckpoint() throws {
        let store = ObservationCheckpointStore(fileURL: makeStoreURL())
        let payable = URL(filePath: "/Developer/payable")
        let anchor = URL(filePath: "/Developer/anchor")

        try store.recordCheckpoint(1, forWorkspaceAt: payable)
        try store.recordCheckpoint(2, forWorkspaceAt: anchor)

        #expect(try store.checkpoint(forWorkspaceAt: payable) == 1)
        #expect(try store.checkpoint(forWorkspaceAt: anchor) == 2)
    }

    @Test("a later checkpoint replaces the one before it")
    func aLaterCheckpointReplacesTheOneBeforeIt() throws {
        let store = ObservationCheckpointStore(fileURL: makeStoreURL())
        let workspace = URL(filePath: "/Developer/payable")

        try store.recordCheckpoint(1, forWorkspaceAt: workspace)
        try store.recordCheckpoint(2, forWorkspaceAt: workspace)

        #expect(try store.checkpoint(forWorkspaceAt: workspace) == 2)
    }
}

@Suite("Checkpoints for workspaces whose path is spelled awkwardly")
struct AwkwardlySpelledWorkspaceCheckpointTests {
    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-checkpoints-\(UUID().uuidString)/checkpoints.json")
    }

    @Test(
        "a workspace under a folder with a space keeps its checkpoint",
        arguments: ["Application Support", "code + notes", "café"]
    )
    func workspaceUnderFolderWithASpaceKeepsItsCheckpoint(folderName: String) throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let workspaceURL = FileManager.default.temporaryDirectory
            .appending(path: folderName)
            .appending(path: "anchor")
        let store = ObservationCheckpointStore(fileURL: fileURL)

        try store.recordCheckpoint(41, forWorkspaceAt: workspaceURL)

        #expect(try store.checkpoint(forWorkspaceAt: workspaceURL) == 41)
    }

    @Test("the same workspace spelled two ways keeps one checkpoint")
    func sameWorkspaceSpelledTwoWaysKeepsOneCheckpoint() throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let workspaceURL = FileManager.default.temporaryDirectory.appending(path: "anchor")
        let trailingSlash = URL(
            filePath: workspaceURL.path(percentEncoded: false) + "/", directoryHint: .isDirectory)
        let store = ObservationCheckpointStore(fileURL: fileURL)

        try store.recordCheckpoint(41, forWorkspaceAt: workspaceURL)
        try store.recordCheckpoint(42, forWorkspaceAt: trailingSlash)

        #expect(try store.checkpoint(forWorkspaceAt: workspaceURL) == 42)

        let stored = try #require(try? Data(contentsOf: fileURL))
        let decoded = try JSONDecoder().decode([String: UInt64].self, from: stored)

        #expect(decoded.count == 1)
    }
}
