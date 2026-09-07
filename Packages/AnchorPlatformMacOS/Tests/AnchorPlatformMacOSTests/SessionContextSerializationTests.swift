import AnchorApplication
import AnchorDomain
import AnchorIntelligence
import AnchorStorage
import CryptoKit
import Foundation
import Testing

@testable import AnchorPlatformMacOS

private actor ConcurrentCallDetectingInference: StatementInferring {
    private var activeCallCount = 0
    private(set) var foundConcurrentCalls = false

    func readiness() async -> InferenceReadiness { .ready }

    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement] {
        activeCallCount += 1
        foundConcurrentCalls = foundConcurrentCalls || activeCallCount > 1
        try await Task.sleep(for: .milliseconds(100))
        activeCallCount -= 1

        return []
    }
}

private actor SerializationTestIndex: AgentTranscriptIndexing {
    func indexTranscript(_ transcript: AgentTranscript) async throws {}
}

private actor SerializationTestKnowledge: AgentSessionKnowledgeRecording {
    private(set) var recordedTexts: [String] = []
    private var remainingRefusalCount: Int

    init(refusalCount: Int = 0) {
        remainingRefusalCount = refusalCount
    }

    func recordKnowledge(
        fromText text: String,
        forProject projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        at instant: Date
    ) async throws {
        guard remainingRefusalCount == 0 else {
            remainingRefusalCount -= 1
            throw SerializationTestRefusal()
        }

        recordedTexts.append(text)
    }
}

private actor SuspendedSuccessfulKnowledge: AgentSessionKnowledgeRecording {
    private var recordingContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var recordingStarted = false
    private var recordingCount = 0
    private(set) var recordedTexts: [String] = []

    func recordKnowledge(
        fromText text: String,
        forProject projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        at instant: Date
    ) async throws {
        recordingCount += 1
        guard recordingCount == 1 else {
            recordedTexts.append(text)
            return
        }

        recordingStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations.removeAll()
        await withCheckedContinuation { recordingContinuation = $0 }
        recordedTexts.append(text)
    }

    func waitUntilRecordingStarts() async {
        guard !recordingStarted else { return }
        await withCheckedContinuation { startContinuations.append($0) }
    }

    func finishRecording() {
        recordingContinuation?.resume()
        recordingContinuation = nil
    }
}

private struct SerializationTestRefusal: Error {}

@Suite("Ordering session context recording")
struct SessionContextSerializationTests {
    @Test("concurrent rebuilds infer one session at a time")
    func concurrentRebuildsInferOneSessionAtATime() async throws {
        let projectID = ProjectID()
        let sessionID = SessionID()
        let instant = Date(timeIntervalSince1970: 1_000)
        let inference = ConcurrentCallDetectingInference()
        let storage = await ContextStorageAssembly.assemble(
            reachingRemote: { nil },
            localRootURL: FileManager.default.temporaryDirectory
                .appending(path: "anchor-\(UUID().uuidString)"),
            key: .init(size: .bits256)
        )
        let context = try await ContextEngineAssembly.makeSessionContext(
            storage: storage, inferringKnowledge: true, statementInference: inference)
        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: instant, updatedAt: instant),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: sessionID, role: .user,
                        content: "a decision was made", timestamp: instant))
            ]
        )
        let made = try #require(SessionArtifact.make(from: transcript, forProject: projectID))
        let sessions = [(artifact: made.artifact, content: made.content)]

        async let first = context.rebuilder.rebuild(from: sessions, at: instant)
        async let second = context.rebuilder.rebuild(from: sessions, at: instant)
        _ = await (first, second)

        #expect(await inference.foundConcurrentCalls == false)
    }

    @Test("a rebuild cannot replace a session already recorded live")
    func rebuildCannotReplaceSessionAlreadyRecordedLive() async throws {
        let projectID = ProjectID()
        let sessionID = SessionID()
        let instant = Date(timeIntervalSince1970: 1_000)
        let knowledge = SerializationTestKnowledge()
        let pipeline = SessionContextActionPipeline(
            action: RecordSessionContextAction(
                index: SerializationTestIndex(), knowledge: knowledge))
        let artifact = try makeSessionArtifact(
            saying: "new decision", projectID: projectID, sessionID: sessionID, at: instant)
        let staleArtifact = try makeSessionArtifact(
            saying: "old decision", projectID: projectID, sessionID: sessionID, at: instant)

        _ = try await pipeline.recordLiveSessionContext(
            request(from: artifact, at: instant.addingTimeInterval(1)))
        let staleReport = try await pipeline.rebuildSessionContext(
            request(from: staleArtifact, at: instant))

        #expect(staleReport == nil)
        #expect(await knowledge.recordedTexts == ["user: new decision"])
    }

    @Test("a live session refused by inference remains eligible for recovery")
    func liveSessionRefusedByInferenceRemainsEligibleForRecovery() async throws {
        let projectID = ProjectID()
        let sessionID = SessionID()
        let instant = Date(timeIntervalSince1970: 1_000)
        let knowledge = SerializationTestKnowledge(refusalCount: 1)
        let pipeline = SessionContextActionPipeline(
            action: RecordSessionContextAction(
                index: SerializationTestIndex(), knowledge: knowledge))
        let sessionArtifact = try makeSessionArtifact(
            saying: "new decision", projectID: projectID, sessionID: sessionID, at: instant)
        let sessionRequest = request(from: sessionArtifact, at: instant)

        let liveReport = try await pipeline.recordLiveSessionContext(sessionRequest)
        let recoveredReport = try #require(
            try await pipeline.rebuildSessionContext(sessionRequest))

        #expect(liveReport.knowledgeRefusal != nil)
        #expect(recoveredReport.knowledgeRefusal == nil)
        #expect(await knowledge.recordedTexts == ["user: new decision"])
    }

    @Test("a rebuild queued during successful live recording is discarded")
    func rebuildQueuedDuringSuccessfulLiveRecordingIsDiscarded() async throws {
        let projectID = ProjectID()
        let sessionID = SessionID()
        let instant = Date(timeIntervalSince1970: 1_000)
        let knowledge = SuspendedSuccessfulKnowledge()
        let pipeline = SessionContextActionPipeline(
            action: RecordSessionContextAction(
                index: SerializationTestIndex(), knowledge: knowledge))
        let sessionArtifact = try makeSessionArtifact(
            saying: "new decision", projectID: projectID, sessionID: sessionID, at: instant)
        let sessionRequest = request(from: sessionArtifact, at: instant)

        let liveRecording = Task {
            try await pipeline.recordLiveSessionContext(sessionRequest)
        }
        await knowledge.waitUntilRecordingStarts()
        let queuedRebuild = Task {
            try await pipeline.rebuildSessionContext(sessionRequest)
        }
        await Task.yield()
        await knowledge.finishRecording()

        _ = try await liveRecording.value
        let rebuildReport = try await queuedRebuild.value

        #expect(rebuildReport == nil)
        #expect(await knowledge.recordedTexts == ["user: new decision"])
    }

    private func makeSessionArtifact(
        saying text: String,
        projectID: ProjectID,
        sessionID: SessionID,
        at instant: Date
    ) throws -> (artifact: Artifact, content: Data) {
        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: instant, updatedAt: instant),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: sessionID, role: .user,
                        content: text, timestamp: instant))
            ]
        )

        return try #require(SessionArtifact.make(from: transcript, forProject: projectID))
    }

    private func request(
        from sessionArtifact: (artifact: Artifact, content: Data), at instant: Date
    ) -> RecordSessionContextRequest {
        RecordSessionContextRequest(
            artifact: sessionArtifact.artifact,
            content: sessionArtifact.content,
            contentHash: ContentHash.digest(of: sessionArtifact.content),
            recordedAt: instant
        )
    }
}
