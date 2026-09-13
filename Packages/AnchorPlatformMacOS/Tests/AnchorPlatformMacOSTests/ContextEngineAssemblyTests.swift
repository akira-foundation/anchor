import AnchorDomain
import AnchorIntelligence
import AnchorKnowledge
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
        let checkpointFile =
            support
            .appending(path: "checkpoints")
            .appending(path: "\(observed.projectID.rawValue).json")
        var reached: [UInt64] = []

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
            reached.append(await waitForCheckpoint(at: checkpointFile, beyond: reached.last))
            await coordinator.stopObserving()
        }

        let written = try FileManager.default.contentsOfDirectory(
            atPath: support.appending(path: "checkpoints").path(percentEncoded: false))

        #expect(written == ["\(observed.projectID.rawValue).json"])
        #expect(reached.count == 2)
        #expect(reached[0] > 0)
        #expect(reached[1] > reached[0])
    }

    private func waitForCheckpoint(at fileURL: URL, beyond previous: UInt64?) async -> UInt64 {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))

        while ContinuousClock.now < deadline {
            let stored =
                (try? JSONDecoder().decode(
                    [String: UInt64].self, from: Data(contentsOf: fileURL)))?.values.first

            guard let stored, stored > (previous ?? 0) else {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }

            return stored
        }

        return 0
    }
}

private actor RecordingStatementInference: StatementInferring {
    private(set) var wasAsked = false

    func readiness() async -> InferenceReadiness { .ready }

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        wasAsked = true

        return []
    }
}

private struct UnavailableStatementInference: StatementInferring {
    func readiness() async -> InferenceReadiness {
        .unavailable("Apple Intelligence is off")
    }

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        []
    }
}

private actor ChangingStatementInference: StatementInferring {
    private var currentReadiness: InferenceReadiness = .unavailable("model is preparing")
    private(set) var wasAsked = false

    func readiness() async -> InferenceReadiness { currentReadiness }

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        wasAsked = true

        return []
    }

    func becomeReady() {
        currentReadiness = .ready
    }
}

@Suite("What the assembly actually built")
struct AssembledKnowledgeExtractorTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()
    private let recordedAt = Date(timeIntervalSince1970: 1_000)

    private func assembleStorage() async -> AssembledContextStorage {
        await ContextStorageAssembly.assemble(
            reachingRemote: { nil },
            localRootURL: FileManager.default.temporaryDirectory
                .appending(path: "anchor-\(UUID().uuidString)"),
            key: SymmetricKey(size: .bits256)
        )
    }

    @Test("the inference driver the assembly was given is reached by a recorded session")
    func inferenceDriverAssemblyWasGivenIsReachedByRecordedSession() async throws {
        let inference = RecordingStatementInference()
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: await assembleStorage(),
            inferringKnowledge: true,
            statementInference: inference
        )
        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: recordedAt, updatedAt: recordedAt),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: sessionID, role: .user,
                        content: "a decision was made", timestamp: recordedAt))
            ]
        )
        let made = try #require(SessionArtifact.make(from: transcript, forProject: projectID))

        let rebuilt = await context.rebuilder.rebuild(
            from: [(artifact: made.artifact, content: made.content)], at: recordedAt)

        #expect(rebuilt.indexedSessions == 1)
        #expect(await inference.wasAsked)
    }

    @Test("inference is reported as disabled when the workspace did not ask for it")
    func inferenceIsReportedAsDisabledWhenWorkspaceDidNotAskForIt() async throws {
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: await assembleStorage())

        #expect(await context.inferenceStatus() == .disabled)
    }

    @Test("an unavailable model is reported without preventing session context")
    func unavailableModelIsReportedWithoutPreventingSessionContext() async throws {
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: await assembleStorage(),
            inferringKnowledge: true,
            statementInference: UnavailableStatementInference()
        )

        #expect(await context.inferenceStatus() == .unavailable("Apple Intelligence is off"))
    }

    @Test("an enabled model that becomes ready starts inferring without restarting")
    func enabledModelThatBecomesReadyStartsInferringWithoutRestarting() async throws {
        let inference = ChangingStatementInference()
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: await assembleStorage(),
            inferringKnowledge: true,
            statementInference: inference
        )

        #expect(await context.inferenceStatus() == .unavailable("model is preparing"))

        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: recordedAt, updatedAt: recordedAt),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: sessionID, role: .user,
                        content: "a decision was made", timestamp: recordedAt))
            ]
        )
        let made = try #require(SessionArtifact.make(from: transcript, forProject: projectID))
        let sessions = [(artifact: made.artifact, content: made.content)]

        let unavailableRebuild = await context.rebuilder.rebuild(
            from: sessions, at: recordedAt)

        #expect(unavailableRebuild.indexedSessions == 1)
        #expect(unavailableRebuild.refusals.count == 1)
        #expect(await inference.wasAsked == false)

        await inference.becomeReady()

        async let firstRecovery = context.rebuildSessionContextIfInferenceBecameReady(
            after: .unavailable("model is preparing"),
            from: sessions,
            at: recordedAt
        )
        async let duplicateRecovery = context.rebuildSessionContextIfInferenceBecameReady(
            after: .unavailable("model is preparing"),
            from: sessions,
            at: recordedAt
        )
        let recoveries = await [firstRecovery, duplicateRecovery].compactMap { $0 }

        #expect(await context.inferenceStatus() == .ready)
        #expect(recoveries.map(\.indexedSessions) == [1])
        #expect(await inference.wasAsked)
    }
}
