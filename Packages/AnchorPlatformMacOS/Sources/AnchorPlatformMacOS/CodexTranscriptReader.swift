import AnchorDomain
import AnchorFoundation
import AnchorProvider
import Foundation

public struct CodexRolloutOrigin: Sendable, Hashable {
    public let sessionID: SessionID
    public let workingDirectory: String
    public let startedByAPerson: Bool
}

public struct CodexTranscriptReader: Sendable {
    private let redactor: SessionSecretRedactor

    public init(redactor: SessionSecretRedactor = SessionSecretRedactor()) {
        self.redactor = redactor
    }

    public func origin(inLineDelimitedJSON text: String) -> CodexRolloutOrigin? {
        for line in text.split(separator: "\n") {
            guard let record = Self.record(from: line),
                record.type == "session_meta",
                let sessionID = (record.payload["session_id"] as? String)
                    .flatMap(SessionID.init(rawValue:)),
                let workingDirectory = record.payload["cwd"] as? String
            else { continue }

            return CodexRolloutOrigin(
                sessionID: sessionID,
                workingDirectory: workingDirectory,
                startedByAPerson: record.payload["thread_source"] as? String == "user"
            )
        }

        return nil
    }

    public func transcript(
        inLineDelimitedJSON text: String, forProject projectID: ProjectID
    ) -> AgentTranscript? {
        guard let origin = origin(inLineDelimitedJSON: text), origin.startedByAPerson else {
            return nil
        }

        let entries = text.split(separator: "\n")
            .compactMap { conversationMessage(fromLine: $0, inSession: origin.sessionID) }
        let instants = entries.map(\.recordedAt)

        guard let startedAt = instants.min(), let updatedAt = instants.max() else { return nil }

        return AgentTranscript(
            session: AgentSession(
                id: origin.sessionID,
                projectID: projectID,
                provider: .codex,
                startedAt: startedAt,
                updatedAt: updatedAt
            ),
            messages: entries.map(\.message)
        )
    }

    private func conversationMessage(
        fromLine line: Substring, inSession sessionID: SessionID
    ) -> (message: ConversationMessage, recordedAt: Date)? {
        guard let record = Self.record(from: line),
            record.type == "response_item",
            record.payload["type"] as? String == "message",
            let role = ConversationRole(rawValue: record.payload["role"] as? String ?? ""),
            let externalIdentifier = record.payload["id"] as? String,
            let recordedAt = Self.instant(from: record.timestamp)
        else { return nil }

        let prose = redactor.redact(Self.prose(in: record.payload["content"]))

        guard !prose.isEmpty else { return nil }

        return (
            ConversationMessage(
                id: MessageID.derived(fromSeed: "\(sessionID.rawValue)/\(externalIdentifier)"),
                sessionID: sessionID,
                role: role,
                content: prose,
                timestamp: recordedAt
            ),
            recordedAt
        )
    }

    private static func record(
        from line: Substring
    ) -> (type: String, timestamp: String, payload: [String: Any])? {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
            let fields = parsed as? [String: Any],
            let type = fields["type"] as? String,
            let timestamp = fields["timestamp"] as? String,
            let payload = fields["payload"] as? [String: Any]
        else { return nil }

        return (type, timestamp, payload)
    }

    private static func prose(in content: Any?) -> String {
        guard let blocks = content as? [[String: Any]] else { return "" }

        return
            blocks
            .filter { ["input_text", "output_text", "text"].contains($0["type"] as? String ?? "") }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }

    private static func instant(from timestamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return fractional.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }
}
