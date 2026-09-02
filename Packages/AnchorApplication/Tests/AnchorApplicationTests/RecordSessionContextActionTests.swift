import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

private actor RecordingIndex: AgentTranscriptIndexing {
    private(set) var indexed: [AgentTranscript] = []
    private let refusal: (any Error)?

    init(refusing refusal: (any Error)? = nil) { self.refusal = refusal }

    func indexTranscript(_ transcript: AgentTranscript) async throws {
        if let refusal { throw refusal }

        indexed.append(transcript)
    }
}

private actor RecordingKnowledge: AgentSessionKnowledgeRecording {
    struct Recorded: Sendable, Equatable {
        let text: String
        let source: KnowledgeEntrySource
        let contentHash: ContentHash
    }

    private(set) var recorded: [Recorded] = []

    func recordKnowledge(
        fromText text: String,
        forProject projectID: ProjectID,
        source: KnowledgeEntrySource,
        sourceContentHash: ContentHash,
        at instant: Date
    ) async throws {
        recorded.append(Recorded(text: text, source: source, contentHash: sourceContentHash))
    }
}

private struct IndexRefusal: Error {}

@Suite("Turning a recorded session into something that can be asked about")
struct RecordSessionContextActionTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()
    private let recordedAt = Date(timeIntervalSince1970: 1_000)

    private func makeTranscript(
        messages: [(role: ConversationRole, content: String)]
    ) -> AgentTranscript {
        let session = AgentSession(
            id: sessionID,
            projectID: projectID,
            provider: .claude,
            startedAt: recordedAt,
            updatedAt: recordedAt
        )
        let entries = messages.enumerated().map { offset, message in
            ConversationEntry.message(
                ConversationMessage(
                    id: MessageID(),
                    sessionID: sessionID,
                    role: message.role,
                    content: message.content,
                    timestamp: recordedAt.addingTimeInterval(Double(offset))
                ))
        }

        return AgentTranscript(session: session, entries: entries)
    }

    private func makeArtifact(
        named name: String, provider: AgentProvider = .claude
    ) throws
        -> Artifact
    {
        try #require(
            Artifact(id: ArtifactID(), projectID: projectID, provider: provider, name: name))
    }

    private func encode(_ transcript: AgentTranscript) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(transcript.inConversationOrder)
    }

    private func makeRequest(
        transcript: AgentTranscript, name: String? = nil
    ) throws -> RecordSessionContextRequest {
        let content = try encode(transcript)

        return RecordSessionContextRequest(
            artifact: try makeArtifact(
                named: name
                    ?? AgentSessionArtifactNaming.name(
                        forSession: sessionID, provider: .claude)),
            content: content,
            contentHash: ContentHash.digest(of: content),
            recordedAt: recordedAt
        )
    }

    @Test("a recorded session becomes an indexed session")
    func recordedSessionBecomesIndexedSession() async throws {
        let transcript = makeTranscript(messages: [
            (.user, "how do I ship this"), (.assistant, "like so"),
        ])
        let index = RecordingIndex()
        let knowledge = RecordingKnowledge()

        let outcome = try await RecordSessionContextAction(index: index, knowledge: knowledge)
            .perform(try makeRequest(transcript: transcript))

        #expect(outcome == .indexed(messageCount: 2))
        #expect(await index.indexed.map(\.session.id) == [sessionID])
    }

    @Test("an artifact that is not a session is left alone")
    func artifactThatIsNotSessionIsLeftAlone() async throws {
        let transcript = makeTranscript(messages: [(.user, "hello")])
        let index = RecordingIndex()
        let knowledge = RecordingKnowledge()

        let outcome = try await RecordSessionContextAction(index: index, knowledge: knowledge)
            .perform(
                try makeRequest(transcript: transcript, name: "docs/superpowers/plans/00.md"))

        #expect(outcome == .notASession)
        #expect(await index.indexed.isEmpty)
        #expect(await knowledge.recorded.isEmpty)
    }

    @Test("a session whose content is not a transcript is refused rather than ignored")
    func sessionWhoseContentIsNotTranscriptIsRefusedRatherThanIgnored() async throws {
        let content = Data("not a transcript".utf8)
        let request = RecordSessionContextRequest(
            artifact: try makeArtifact(
                named: AgentSessionArtifactNaming.name(forSession: sessionID, provider: .claude)),
            content: content,
            contentHash: ContentHash.digest(of: content),
            recordedAt: recordedAt
        )

        await #expect(throws: RecordSessionContextFailure.self) {
            try await RecordSessionContextAction(
                index: RecordingIndex(), knowledge: RecordingKnowledge()
            ).perform(request)
        }
    }

    @Test("what the knowledge reads is the prose, not the machinery")
    func whatKnowledgeReadsIsProseNotMachinery() async throws {
        let transcript = makeTranscript(
            messages: [(.user, "DECISION: keep the journal local"), (.assistant, "understood")])
        let knowledge = RecordingKnowledge()

        _ = try await RecordSessionContextAction(index: RecordingIndex(), knowledge: knowledge)
            .perform(try makeRequest(transcript: transcript))

        let recorded = try #require(await knowledge.recorded.first)

        #expect(recorded.text.contains("DECISION: keep the journal local"))
        #expect(recorded.text.contains("understood"))
    }

    @Test("the knowledge points at the session it came from")
    func knowledgePointsAtSessionItCameFrom() async throws {
        let transcript = makeTranscript(messages: [(.user, "TODO: wire the search")])
        let knowledge = RecordingKnowledge()
        let request = try makeRequest(transcript: transcript)

        _ = try await RecordSessionContextAction(index: RecordingIndex(), knowledge: knowledge)
            .perform(request)

        let recorded = try #require(await knowledge.recorded.first)

        #expect(recorded.source == .session(sessionID))
        #expect(recorded.contentHash == request.contentHash)
    }

    @Test("a session that could not be indexed does not quietly record its knowledge")
    func sessionThatCouldNotBeIndexedDoesNotQuietlyRecordItsKnowledge() async throws {
        let transcript = makeTranscript(messages: [(.user, "TODO: wire the search")])
        let knowledge = RecordingKnowledge()

        await #expect(throws: IndexRefusal.self) {
            try await RecordSessionContextAction(
                index: RecordingIndex(refusing: IndexRefusal()), knowledge: knowledge
            ).perform(try makeRequest(transcript: transcript))
        }

        #expect(await knowledge.recorded.isEmpty)
    }
}
