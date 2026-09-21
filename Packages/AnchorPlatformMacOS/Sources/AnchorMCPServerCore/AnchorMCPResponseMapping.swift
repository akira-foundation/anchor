import AnchorApplication
import AnchorDomain
import Foundation
import MCP

extension AnchorMCPToolRouter {
    func timestampValue(_ timestamp: Date) -> Value { .string(timestamp.ISO8601Format()) }

    func projectFields(_ project: ProjectContext) -> [String: Value] {
        var fields: [String: Value] = [
            "project_id": .string(project.projectID.rawValue), "name": .string(project.displayName),
            "workspace_path": .string(project.workspaceURL.path),
        ]
        if let remote = project.canonicalRepositoryRemote {
            fields["canonical_remote"] = .string(remote.rawValue)
        }
        return fields
    }

    func artifactFields(_ artifact: Artifact) -> [String: Value] {
        [
            "artifact_id": .string(artifact.id.rawValue), "name": .string(artifact.name),
            "provider": .string(artifact.provider.rawValue),
        ]
    }

    func artifactRecordFields(_ record: ArtifactContextRecord) -> Value {
        var fields = artifactFields(record.artifact)
        if let revision = record.latestRevision {
            fields["revision_id"] = .string(revision.id.rawValue)
            fields["content_hash"] = .string(revision.contentHash.rawValue)
            fields["updated_at"] = timestampValue(revision.createdAt)
        }
        return .object(fields)
    }

    func sessionFields(_ session: AgentSession) -> [String: Value] {
        var fields: [String: Value] = [
            "session_id": .string(session.id.rawValue),
            "provider": .string(session.provider.rawValue),
            "started_at": timestampValue(session.startedAt),
            "updated_at": timestampValue(session.updatedAt),
        ]
        if let parent = session.parentSessionID {
            fields["parent_session_id"] = .string(parent.rawValue)
        }
        return fields
    }

    func sessionRecordFields(_ record: SessionContextRecord) -> Value {
        var fields = sessionFields(record.session)
        fields["message_count"] = .int(record.messageCount)
        fields["tool_activity_count"] = .int(record.toolActivityCount)
        return .object(fields)
    }

    func searchFields(_ hit: ProjectContextSearchHit) -> Value {
        let kind: String
        switch hit.kind {
        case .message(let role): kind = role.rawValue
        case .toolActivity: kind = "tool_activity"
        }
        return .object([
            "session_id": .string(hit.sessionID.rawValue),
            "provider": .string(hit.provider.rawValue), "kind": .string(kind),
            "excerpt": .string(hit.excerpt), "timestamp": timestampValue(hit.timestamp),
        ])
    }

    func entryFields(_ entry: ConversationEntry) -> Value {
        switch entry {
        case .message(let message):
            return .object([
                "entry_kind": .string("message"), "message_id": .string(message.id.rawValue),
                "role": .string(message.role.rawValue), "content": .string(message.content),
                "timestamp": timestampValue(message.timestamp),
            ])
        case .toolActivity(let activity):
            var fields: [String: Value] = [
                "entry_kind": .string("tool_activity"),
                "activity_id": .string(activity.id.rawValue),
                "tool_name": .string(activity.toolName), "invocation": .string(activity.invocation),
                "failed": .bool(activity.failed), "timestamp": timestampValue(activity.timestamp),
            ]
            if let outcome = activity.outcome { fields["outcome"] = .string(outcome) }
            return .object(fields)
        }
    }

    func pageFields(_ records: [Value], cursor: ContextPageCursor?, key: String) -> Value {
        var fields: [String: Value] = [key: .array(records)]
        if let cursor { fields["next_cursor"] = .string(cursor.rawValue) }
        return .object(fields)
    }
}
