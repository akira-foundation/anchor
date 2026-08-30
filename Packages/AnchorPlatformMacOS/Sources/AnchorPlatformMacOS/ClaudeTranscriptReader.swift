import AnchorDomain
import AnchorProvider
import Foundation

struct ClaudeEntry {
    let sessionID: SessionID
    let entry: ConversationEntry
}

struct ClaudeToolOutcome {
    let output: String
    let failed: Bool
}

public struct ClaudeTranscriptReader: Sendable {
    private let redactor: SessionSecretRedactor

    public init(redactor: SessionSecretRedactor = SessionSecretRedactor()) {
        self.redactor = redactor
    }

    public func transcripts(
        inLineDelimitedJSON text: String, forProject projectID: ProjectID
    ) -> [AgentTranscript] {
        let lines = text.split(separator: "\n")
        let outcomes = Self.toolOutcomes(in: lines)
        let entries =
            lines.compactMap(conversationMessage(fromLine:))
            + lines.flatMap { toolActivities(fromLine: $0, pairedWith: outcomes) }
        let entriesBySession = Dictionary(grouping: entries, by: \.sessionID)

        return entriesBySession.keys.sorted { $0.rawValue < $1.rawValue }
            .compactMap { sessionID in
                transcript(
                    forSession: sessionID,
                    from: entriesBySession[sessionID] ?? [],
                    forProject: projectID
                )
            }
    }

    private func transcript(
        forSession sessionID: SessionID,
        from entries: [ClaudeEntry],
        forProject projectID: ProjectID
    ) -> AgentTranscript? {
        let instants = entries.map(\.entry.timestamp)

        guard let startedAt = instants.min(), let updatedAt = instants.max() else { return nil }

        return AgentTranscript(
            session: AgentSession(
                id: sessionID,
                projectID: projectID,
                provider: .claude,
                startedAt: startedAt,
                updatedAt: updatedAt
            ),
            entries: entries.map(\.entry)
        )
    }

    private func conversationMessage(fromLine line: Substring) -> ClaudeEntry? {
        guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
            let fields = record as? [String: Any],
            let role = ConversationRole(rawValue: fields["type"] as? String ?? ""),
            let sessionID = (fields["sessionId"] as? String).flatMap(SessionID.init(rawValue:)),
            let messageID = (fields["uuid"] as? String).flatMap(MessageID.init(rawValue:)),
            let recordedAt = (fields["timestamp"] as? String).flatMap(Self.instant(from:))
        else { return nil }

        let prose = redactor.redact(Self.prose(in: fields["message"]))

        guard !prose.isEmpty else { return nil }

        return ClaudeEntry(
            sessionID: sessionID,
            entry: .message(
                ConversationMessage(
                    id: messageID,
                    sessionID: sessionID,
                    role: role,
                    content: prose,
                    timestamp: recordedAt
                )
            )
        )
    }

    private func toolActivities(
        fromLine line: Substring, pairedWith outcomes: [String: ClaudeToolOutcome]
    ) -> [ClaudeEntry] {
        guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
            let fields = record as? [String: Any],
            fields["type"] as? String == "assistant",
            let sessionID = (fields["sessionId"] as? String).flatMap(SessionID.init(rawValue:)),
            let recordedAt = (fields["timestamp"] as? String).flatMap(Self.instant(from:)),
            let message = fields["message"] as? [String: Any],
            let blocks = message["content"] as? [[String: Any]]
        else { return [] }

        return blocks.filter { $0["type"] as? String == "tool_use" }
            .compactMap { block in
                guard let callIdentifier = block["id"] as? String,
                    let toolName = block["name"] as? String
                else { return nil }

                let outcome = outcomes[callIdentifier]

                return ClaudeEntry(
                    sessionID: sessionID,
                    entry: .toolActivity(
                        ToolActivity(
                            id: ToolActivityID.derived(
                                fromSeed: "\(sessionID.rawValue)/\(callIdentifier)"),
                            sessionID: sessionID,
                            toolName: toolName,
                            invocation: redactor.redact(ToolOutput.summarised(block["input"])),
                            outcome: outcome.map { redactor.redact($0.output) },
                            failed: outcome?.failed ?? false,
                            timestamp: recordedAt
                        )
                    )
                )
            }
    }

    private static func toolOutcomes(in lines: [Substring]) -> [String: ClaudeToolOutcome] {
        var outcomes: [String: ClaudeToolOutcome] = [:]

        for line in lines {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                let fields = record as? [String: Any],
                let message = fields["message"] as? [String: Any],
                let blocks = message["content"] as? [[String: Any]]
            else { continue }

            for block in blocks where block["type"] as? String == "tool_result" {
                guard let callIdentifier = block["tool_use_id"] as? String else { continue }

                outcomes[callIdentifier] = ClaudeToolOutcome(
                    output: ToolOutput.summarised(block["content"]),
                    failed: block["is_error"] as? Bool ?? false
                )
            }
        }

        return outcomes
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
