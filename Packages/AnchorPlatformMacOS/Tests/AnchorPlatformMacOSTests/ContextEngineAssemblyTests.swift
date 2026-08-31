import AnchorDomain
import AnchorStorage
import CryptoKit
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("The engine this machine assembles", .serialized)
struct ContextEngineAssemblyTests {
    private let encryptionKey = SymmetricKey(size: .bits256)

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "anchor-\(UUID().uuidString)")
    }

    private func assembleStorage(reachingAccount: Bool) async -> AssembledContextStorage {
        await ContextStorageAssembly.assemble(
            reachingRemote: { reachingAccount ? InMemoryStorageProvider() : nil },
            localRootURL: temporaryDirectoryURL(),
            key: encryptionKey
        )
    }

    @Test("a machine with an account observes and then stops")
    func machineWithAnAccountObservesAndThenStops() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let support = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: support) }

        let coordinator = ContextEngineAssembly.makeCoordinator(
            device: Device(id: DeviceID(), displayName: "Studio", platform: .macOS),
            observedWorkspace: ObservedWorkspace(
                workspaceURL: workspace, projectName: "anchor"),
            storage: await assembleStorage(reachingAccount: true),
            supportDirectoryURL: support
        )

        try await coordinator.startObserving(
            workspaceAt: workspace, forProject: ProjectID.derived(fromSeed: "anchor"))

        #expect(await coordinator.isObserving)

        await coordinator.stopObserving()

        #expect(await coordinator.isObserving == false)
    }

    @Test("a machine without an account still observes rather than refusing to start")
    func machineWithoutAnAccountStillObservesRatherThanRefusingToStart() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let support = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: support) }

        let coordinator = ContextEngineAssembly.makeCoordinator(
            device: Device(id: DeviceID(), displayName: "Studio", platform: .macOS),
            observedWorkspace: ObservedWorkspace(
                workspaceURL: workspace, projectName: "anchor"),
            storage: await assembleStorage(reachingAccount: false),
            supportDirectoryURL: support
        )

        try await coordinator.startObserving(
            workspaceAt: workspace, forProject: ProjectID.derived(fromSeed: "anchor"))

        #expect(await coordinator.isObserving)

        await coordinator.stopObserving()
    }

    @Test("the checkpoint a run writes is the one the next run reads")
    func checkpointRunWritesIsOneNextRunReads() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let support = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: support) }

        let observed = ObservedWorkspace(workspaceURL: workspace, projectName: "anchor")
        let storage = await assembleStorage(reachingAccount: false)
        let checkpointDirectory = support.appending(path: "checkpoints")

        for run in 1...2 {
            let coordinator = ContextEngineAssembly.makeCoordinator(
                device: Device(id: DeviceID(), displayName: "Studio", platform: .macOS),
                observedWorkspace: observed,
                storage: storage,
                supportDirectoryURL: support
            )

            try await coordinator.startObserving(
                workspaceAt: workspace, forProject: observed.projectID)
            try Data("plan revised on run \(run)".utf8)
                .write(to: workspace.appending(path: "docs/superpowers/plans/00-indice.md"))
            _ = await waitForCheckpoint(in: checkpointDirectory)
            await coordinator.stopObserving()
        }

        let written = try FileManager.default.contentsOfDirectory(
            atPath: checkpointDirectory.path(percentEncoded: false))

        #expect(written == ["\(observed.projectID.rawValue).json"])
    }

    private func waitForCheckpoint(in directoryURL: URL) async -> [String] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))

        while ContinuousClock.now < deadline {
            let written =
                (try? FileManager.default.contentsOfDirectory(
                    atPath: directoryURL.path(percentEncoded: false))) ?? []

            guard written.isEmpty else { return written }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return []
    }
}
