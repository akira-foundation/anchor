import AnchorApplication
import AnchorDomain

extension SQLiteContextSearch {
    public func replaceTranscripts(
        _ transcripts: [AgentTranscript], forProject projectID: ProjectID
    ) async throws {
        guard transcripts.allSatisfy({ $0.session.projectID == projectID }) else {
            throw ContextReplacementFailure.projectMismatch
        }
        guard
            transcripts.allSatisfy({ transcript in
                transcript.entries.allSatisfy { entry in
                    switch entry {
                    case .message(let message): message.sessionID == transcript.session.id
                    case .toolActivity(let activity): activity.sessionID == transcript.session.id
                    }
                }
            })
        else { throw ContextReplacementFailure.invalidTranscript }
        try await database.withinTransaction { isolatedDatabase in
            for transcript in transcripts {
                let existing = try isolatedDatabase.run(
                    "SELECT project_id FROM context_sessions WHERE session_id = ?;",
                    [.text(transcript.session.id.rawValue)])
                guard existing.first?["project_id"]?.text.map({ $0 == projectID.rawValue }) ?? true
                else {
                    throw ContextReplacementFailure.projectMismatch
                }
            }
            for table in ["message_text", "tool_text"] {
                try isolatedDatabase.run(
                    "DELETE FROM \(table) WHERE session_id IN (SELECT session_id FROM context_sessions WHERE project_id = ?);",
                    [.text(projectID.rawValue)])
            }
            try isolatedDatabase.run(
                "DELETE FROM context_sessions WHERE project_id = ?;", [.text(projectID.rawValue)])
            for transcript in transcripts {
                try Self.replaceTranscript(transcript, in: isolatedDatabase)
            }
        }
    }
}
