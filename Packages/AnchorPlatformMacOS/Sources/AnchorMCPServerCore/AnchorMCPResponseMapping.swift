import AnchorApplication
import AnchorDomain
import Foundation
import MCP

extension AnchorMCPToolRouter {
    func timestampValue(_ timestamp: Date) -> Value { .string(timestamp.ISO8601Format()) }

    func projectFields(_ project: ProjectContext) -> [String: Value] {
        var fields: [String: Value] = ["project_id": .string(project.projectID.rawValue)]
        assignBoundedText(project.displayName, field: "name", fields: &fields)
        assignBoundedText(project.workspaceURL.path, field: "workspace_path", fields: &fields)
        if let remote = project.canonicalRepositoryRemote {
            assignBoundedText(remote.rawValue, field: "canonical_remote", fields: &fields)
        }
        return fields
    }

    func artifactFields(_ artifact: Artifact) -> [String: Value] {
        var fields: [String: Value] = [
            "artifact_id": .string(artifact.id.rawValue),
            "provider": .string(artifact.provider.rawValue),
        ]
        assignBoundedText(artifact.name, field: "name", fields: &fields)
        return fields
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
        var fields: [String: Value] = [
            "session_id": .string(hit.sessionID.rawValue),
            "provider": .string(hit.provider.rawValue), "kind": .string(kind),
            "timestamp": timestampValue(hit.timestamp),
        ]
        assignBoundedText(hit.excerpt, field: "excerpt", fields: &fields)
        return .object(fields)
    }

    func entryFields(_ entry: ConversationEntry) -> Value {
        switch entry {
        case .message(let message):
            let content = boundedResponseText(message.content)
            return .object([
                "entry_kind": .string("message"), "message_id": .string(message.id.rawValue),
                "role": .string(message.role.rawValue), "content": .string(content.text),
                "content_is_truncated": .bool(content.isTruncated),
                "timestamp": timestampValue(message.timestamp),
            ])
        case .toolActivity(let activity):
            let toolName = boundedResponseText(activity.toolName)
            let invocation = boundedResponseText(activity.invocation)
            var fields: [String: Value] = [
                "entry_kind": .string("tool_activity"),
                "activity_id": .string(activity.id.rawValue),
                "tool_name": .string(toolName.text),
                "tool_name_is_truncated": .bool(toolName.isTruncated),
                "invocation": .string(invocation.text),
                "invocation_is_truncated": .bool(invocation.isTruncated),
                "failed": .bool(activity.failed), "timestamp": timestampValue(activity.timestamp),
            ]
            if let outcome = activity.outcome {
                let boundedOutcome = boundedResponseText(outcome)
                fields["outcome"] = .string(boundedOutcome.text)
                fields["outcome_is_truncated"] = .bool(boundedOutcome.isTruncated)
            }
            return .object(fields)
        }
    }

    private func assignBoundedText(
        _ content: String, field: String, fields: inout [String: Value]
    ) {
        let boundedContent = boundedResponseText(content)
        fields[field] = .string(boundedContent.text)
        if boundedContent.isTruncated {
            fields["\(field)_is_truncated"] = .bool(true)
        }
    }

    private func boundedResponseText(_ content: String) -> (text: String, isTruncated: Bool) {
        let maximumBytes = 16_384
        guard content.utf8.count > maximumBytes else { return (content, false) }
        let marker = "… [truncated]"
        let prefixByteLimit = maximumBytes - marker.utf8.count
        var prefix = ""
        var prefixByteCount = 0
        for scalar in content.unicodeScalars {
            let scalarText = String(scalar)
            let scalarByteCount = scalarText.utf8.count
            guard prefixByteCount + scalarByteCount <= prefixByteLimit else { break }
            prefix.append(scalarText)
            prefixByteCount += scalarByteCount
        }
        return (prefix + marker, true)
    }

    func pageFields(_ records: [Value], cursor: ContextPageCursor?, key: String) -> Value {
        var fields: [String: Value] = [key: .array(records)]
        if let cursor { fields["next_cursor"] = .string(cursor.rawValue) }
        return .object(fields)
    }
}
