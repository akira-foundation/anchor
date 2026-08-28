import AnchorDomain
import AnchorProvider
import Foundation

public struct ClaudeTranscript: Sendable, Hashable {
    public let session: AgentSession
    public let messages: [ConversationMessage]

    public init(session: AgentSession, messages: [ConversationMessage]) {
        self.session = session
        self.messages = messages
    }
}

public struct ClaudeTranscriptReader: Sendable {
    private let redactor: SessionSecretRedactor

    public init(redactor: SessionSecretRedactor = SessionSecretRedactor()) {
        self.redactor = redactor
    }

    public func transcripts(
        inLineDelimitedJSON text: String, forProject projectID: ProjectID
    ) -> [ClaudeTranscript] {
        let messagesBySession = Dictionary(
            grouping: text.split(separator: "\n").compactMap(conversationMessage(fromLine:)),
            by: \.message.sessionID
        )

        return messagesBySession.keys.sorted { $0.rawValue < $1.rawValue }
            .compactMap { sessionID in
                transcript(
                    forSession: sessionID,
                    from: messagesBySession[sessionID] ?? [],
                    forProject: projectID
                )
            }
    }

    private func transcript(
        forSession sessionID: SessionID,
        from entries: [(message: ConversationMessage, recordedAt: Date)],
        forProject projectID: ProjectID
    ) -> ClaudeTranscript? {
        let instants = entries.map(\.recordedAt)

        guard let startedAt = instants.min(), let updatedAt = instants.max() else { return nil }

        return ClaudeTranscript(
            session: AgentSession(
                id: sessionID,
                projectID: projectID,
                provider: .claude,
                startedAt: startedAt,
                updatedAt: updatedAt
            ),
            messages: entries.map(\.message)
        )
    }

    private func conversationMessage(
        fromLine line: Substring
    ) -> (message: ConversationMessage, recordedAt: Date)? {
        guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
            let fields = record as? [String: Any],
            let role = ConversationRole(rawValue: fields["type"] as? String ?? ""),
            let sessionID = (fields["sessionId"] as? String).flatMap(SessionID.init(rawValue:)),
            let messageID = (fields["uuid"] as? String).flatMap(MessageID.init(rawValue:)),
            let recordedAt = (fields["timestamp"] as? String).flatMap(Self.instant(from:))
        else { return nil }

        let prose = redactor.redact(Self.prose(in: fields["message"]))

        guard !prose.isEmpty else { return nil }

        return (
            ConversationMessage(
                id: messageID,
                sessionID: sessionID,
                role: role,
                content: prose,
                timestamp: recordedAt
            ),
            recordedAt
        )
    }

    private static func prose(in message: Any?) -> String {
        guard let message = message as? [String: Any] else { return "" }

        if let text = message["content"] as? String { return text }

        guard let blocks = message["content"] as? [[String: Any]] else { return "" }

        return
            blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }

    private static func instant(from timestamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return fractional.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }
}
