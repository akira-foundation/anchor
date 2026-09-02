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

public enum RecordSessionContextFailure: Error, Sendable, Equatable {
    case contentIsNotATranscript(ArtifactID)
}

public struct RecordSessionContextAction: Action {
    private let index: any AgentTranscriptIndexing
    private let knowledge: any AgentSessionKnowledgeRecording

    public init(index: any AgentTranscriptIndexing, knowledge: any AgentSessionKnowledgeRecording) {
        self.index = index
        self.knowledge = knowledge
    }

    public func perform(
        _ request: RecordSessionContextRequest
    ) async throws -> RecordSessionContextOutcome {
        guard request.artifact.isAgentSessionTranscript else { return .notASession }

        let transcript = try decodeTranscript(in: request)

        try await index.indexTranscript(transcript)

        let messages = transcript.inConversationOrder.messages
        try await knowledge.recordKnowledge(
            fromText: messages.map(\.content).joined(separator: "\n"),
            forProject: request.artifact.projectID,
            source: .session(transcript.session.id),
            sourceContentHash: request.contentHash,
            at: request.recordedAt
        )

        return .indexed(messageCount: messages.count)
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
