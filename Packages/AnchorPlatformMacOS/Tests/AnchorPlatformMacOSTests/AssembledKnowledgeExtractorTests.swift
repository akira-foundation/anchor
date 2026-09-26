import AnchorDomain
import AnchorIntelligence
import AnchorPersistence
import AnchorStorage
import CryptoKit
import Foundation
import Testing

@testable import AnchorPlatformMacOS

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

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] { [] }
}

private actor ChangingStatementInference: StatementInferring {
    private var currentReadiness: InferenceReadiness = .unavailable("model is preparing")
    private(set) var wasAsked = false

    func readiness() async -> InferenceReadiness { currentReadiness }

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        wasAsked = true
        return []
    }

    func becomeReady() { currentReadiness = .ready }
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
            statementInference: inference,
            database: SQLiteDatabase(fileURL: nil)
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
            storage: await assembleStorage(), database: SQLiteDatabase(fileURL: nil))
        #expect(await context.inferenceStatus() == .disabled)
    }

    @Test("an unavailable model is reported without preventing session context")
    func unavailableModelIsReportedWithoutPreventingSessionContext() async throws {
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: await assembleStorage(),
            inferringKnowledge: true,
            statementInference: UnavailableStatementInference(),
            database: SQLiteDatabase(fileURL: nil)
        )
        #expect(await context.inferenceStatus() == .unavailable("Apple Intelligence is off"))
    }

    @Test("an enabled model that becomes ready starts inferring without restarting")
    func enabledModelThatBecomesReadyStartsInferringWithoutRestarting() async throws {
        let inference = ChangingStatementInference()
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: await assembleStorage(),
            inferringKnowledge: true,
            statementInference: inference,
            database: SQLiteDatabase(fileURL: nil)
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
            after: .unavailable("model is preparing"), from: sessions, at: recordedAt)
        async let duplicateRecovery = context.rebuildSessionContextIfInferenceBecameReady(
            after: .unavailable("model is preparing"), from: sessions, at: recordedAt)
        let recoveries = await [firstRecovery, duplicateRecovery].compactMap { $0 }

        #expect(await context.inferenceStatus() == .ready)
        #expect(recoveries.map(\.indexedSessions) == [1])
        #expect(await inference.wasAsked)
    }
}
