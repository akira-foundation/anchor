import AnchorDomain
import Foundation

public struct RecordSessionContextRequest: Sendable {
    public let artifact: Artifact
    public let content: Data
    public let contentHash: ContentHash
    public let recordedAt: Date

    public init(artifact: Artifact, content: Data, contentHash: ContentHash, recordedAt: Date) {
        self.artifact = artifact
        self.content = content
        self.contentHash = contentHash
        self.recordedAt = recordedAt
    }
}

public enum RecordSessionContextOutcome: Sendable, Equatable {
    case indexed(messageCount: Int)
    case notASession
}

public struct RecordSessionContextReport: Sendable, Equatable {
    public let outcome: RecordSessionContextOutcome
    public let knowledgeRefusal: String?
}

public enum RecordSessionContextFailure: Error, Sendable, Equatable {
    case contentIsNotATranscript(ArtifactID)
}

public struct RecordSessionContextAction: Action {
    private let index: any AgentTranscriptIndexing
    private let recordKnowledge:
        @Sendable (
            [ConversationMessage], ProjectID, KnowledgeEntrySource, ContentHash, Date
        ) async throws -> Void

    public init(index: any AgentTranscriptIndexing, knowledge: any AgentSessionKnowledgeRecording) {
        self.index = index
        recordKnowledge = { messages, projectID, source, sourceContentHash, instant in
            try await knowledge.recordKnowledge(
                fromText: messages.map { "\($0.role.rawValue): \($0.content)" }
                    .joined(separator: "\n"),
                forProject: projectID,
                source: source,
                sourceContentHash: sourceContentHash,
                at: instant
            )
        }
    }

    public init(
        index: any AgentTranscriptIndexing,
        conversationKnowledge: any AgentConversationKnowledgeRecording
    ) {
        self.index = index
        recordKnowledge = { messages, projectID, source, sourceContentHash, instant in
            try await conversationKnowledge.recordKnowledge(
                fromMessages: messages,
                forProject: projectID,
                source: source,
                sourceContentHash: sourceContentHash,
                at: instant
            )
        }
    }

    public func perform(
        _ request: RecordSessionContextRequest
    ) async throws -> RecordSessionContextOutcome {
        guard let prepared = try await prepareSessionContext(from: request) else {
            return .notASession
        }

        try await recordKnowledge(
            from: prepared.messages, for: request, sessionID: prepared.sessionID)

        return .indexed(messageCount: prepared.messages.count)
    }

    public func recordSessionContext(
        _ request: RecordSessionContextRequest
    ) async throws -> RecordSessionContextReport {
        guard let prepared = try await prepareSessionContext(from: request) else {
            return RecordSessionContextReport(outcome: .notASession, knowledgeRefusal: nil)
        }

        do {
            try await recordKnowledge(
                from: prepared.messages, for: request, sessionID: prepared.sessionID)

            return RecordSessionContextReport(
                outcome: .indexed(messageCount: prepared.messages.count), knowledgeRefusal: nil)
        } catch {
            return RecordSessionContextReport(
                outcome: .indexed(messageCount: prepared.messages.count),
                knowledgeRefusal: "\(error)")
        }
    }

    private func prepareSessionContext(
        from request: RecordSessionContextRequest
    ) async throws -> (messages: [ConversationMessage], sessionID: SessionID)? {
        guard request.artifact.isAgentSessionTranscript else { return nil }

        let transcript = try decodeTranscript(in: request)

        try await index.indexTranscript(transcript)

        return (transcript.inConversationOrder.messages, transcript.session.id)
    }

    private func recordKnowledge(
        from messages: [ConversationMessage],
        for request: RecordSessionContextRequest,
        sessionID: SessionID
    ) async throws {
        try await recordKnowledge(
            messages,
            request.artifact.projectID,
            .session(sessionID),
            request.contentHash,
            request.recordedAt
        )
    }

    private func decodeTranscript(
        in request: RecordSessionContextRequest
    ) throws(RecordSessionContextFailure) -> AgentTranscript {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let transcript = try? decoder.decode(AgentTranscript.self, from: request.content)
        else { throw .contentIsNotATranscript(request.artifact.id) }

        return transcript
    }
}
