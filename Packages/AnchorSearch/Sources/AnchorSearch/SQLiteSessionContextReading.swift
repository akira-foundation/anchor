import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation

extension SQLiteContextSearch {
    private static let sessionSelection = """
        SELECT session_id, project_id, provider, started_at, updated_at, parent_session_id,
            (SELECT COUNT(*) FROM context_entries e WHERE e.session_id = context_sessions.session_id
                AND e.entry_kind = 'message') AS message_count,
            (SELECT COUNT(*) FROM context_entries e WHERE e.session_id = context_sessions.session_id
                AND e.entry_kind = 'toolActivity') AS tool_count
        """

    public func loadConversationEntries(
        inSession sessionID: SessionID, forProject projectID: ProjectID,
        page: ContextPageRequest, binding: ContextCursorBinding
    ) async throws -> ContextPage<ConversationEntry> {
        try await database.withinTransaction { isolatedDatabase in
            try Self.loadConversationPage(
                inSession: sessionID, page: page, expectedProjectID: projectID,
                binding: binding,
                from: isolatedDatabase)
        }
    }

    public func listSessions(
        forProject projectID: ProjectID,
        provider: AgentProvider?,
        page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<SessionContextRecord> {
        let providerFilter = provider?.rawValue ?? ""
        let cursorPosition = try SQLiteContextCursor.decode(
            page.cursor,
            operation: .listSessions,
            scopeBinding: projectID.rawValue,
            filterBinding: providerFilter, binding: binding)
        var statement = """
            \(Self.sessionSelection)
            FROM context_sessions
            WHERE project_id = ?
            """
        var parameters: [SQLiteValue] = [.text(projectID.rawValue)]

        if let provider {
            statement += " AND provider = ?"
            parameters.append(.text(provider.rawValue))
        }
        if let cursorPosition {
            statement += " AND (updated_at < ? OR (updated_at = ? AND session_id > ?))"
            parameters += [
                .integer(cursorPosition.timestamp), .integer(cursorPosition.timestamp),
                .text(cursorPosition.identifier),
            ]
        }
        statement += " ORDER BY updated_at DESC, session_id ASC LIMIT ?;"
        parameters.append(.integer(Int64(page.limit + 1)))

        let sessionRows = try await database.run(statement, parameters)
        let sessions = try sessionRows.map(Self.sessionRecord)
        let records = Array(sessions.prefix(page.limit))
        let nextCursor =
            try sessionRows.count > page.limit
            ? Self.sessionCursor(
                after: records.last, projectID: projectID, provider: provider,
                binding: binding)
            : nil

        return ContextPage(records: records, nextCursor: nextCursor)
    }

    public func loadSession(
        withIdentifier sessionID: SessionID
    ) async throws -> SessionContextRecord? {
        let sessionRows = try await database.run(
            """
            \(Self.sessionSelection)
            FROM context_sessions WHERE session_id = ? LIMIT 1;
            """,
            [.text(sessionID.rawValue)])
        return try sessionRows.first.map(Self.sessionRecord)
    }

    public func loadMostRecentSession(
        forProject projectID: ProjectID
    ) async throws -> SessionContextRecord? {
        let sessionRows = try await database.run(
            """
            \(Self.sessionSelection)
            FROM context_sessions
            WHERE project_id = ?
            ORDER BY updated_at DESC, session_id ASC
            LIMIT 1;
            """,
            [.text(projectID.rawValue)])
        return try sessionRows.first.map(Self.sessionRecord)
    }

    public func loadConversationEntries(
        inSession sessionID: SessionID,
        page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<ConversationEntry> {
        try await database.withinTransaction { isolatedDatabase in
            try Self.loadConversationPage(
                inSession: sessionID, page: page, binding: binding, from: isolatedDatabase)
        }
    }

    private static func loadConversationPage(
        inSession sessionID: SessionID,
        page: ContextPageRequest,
        expectedProjectID: ProjectID? = nil,
        binding: ContextCursorBinding,
        from database: isolated SQLiteDatabase
    ) throws -> ContextPage<ConversationEntry> {
        let projectRows = try database.run(
            "SELECT project_id FROM context_sessions WHERE session_id = ? LIMIT 1;",
            [.text(sessionID.rawValue)])
        guard !projectRows.isEmpty else {
            if expectedProjectID != nil { throw ContextQueryFailure.entityNotFound }
            guard page.cursor == nil else { throw ContextCursorFailure.invalid }
            return ContextPage(records: [], nextCursor: nil)
        }
        guard
            let projectID = projectRows.first?["project_id"]?.text.flatMap(
                ProjectID.init(rawValue:))
        else {
            throw SQLiteContextReadFailure.malformedSession
        }
        guard expectedProjectID == nil || expectedProjectID == projectID else {
            throw ContextQueryFailure.entityNotFound
        }
        let cursorPosition = try SQLiteContextCursor.decode(
            page.cursor,
            operation: .loadConversationEntries,
            scopeBinding: Self.conversationScopeBinding(
                projectID: projectID, sessionID: sessionID),
            filterBinding: "", binding: binding)
        var statement = """
            SELECT entry_id, session_id, entry_kind, role_or_tool, body, outcome,
                   failed, recorded_at, ordering_id
            FROM context_entries
            WHERE session_id = ?
            """
        var parameters: [SQLiteValue] = [.text(sessionID.rawValue)]

        if let cursorPosition {
            statement += " AND (recorded_at > ? OR (recorded_at = ? AND ordering_id > ?))"
            parameters += [
                .integer(cursorPosition.timestamp), .integer(cursorPosition.timestamp),
                .text(cursorPosition.identifier),
            ]
        }
        statement += " ORDER BY recorded_at ASC, ordering_id ASC LIMIT ?;"
        parameters.append(.integer(Int64(page.limit + 1)))

        let entryRows = try database.run(statement, parameters)
        let entries = try entryRows.map(Self.conversationEntry)
        let records = Array(entries.prefix(page.limit))
        let nextCursor =
            try entryRows.count > page.limit
            ? Self.entryCursor(
                after: records.last, projectID: projectID, sessionID: sessionID,
                binding: binding)
            : nil

        return ContextPage(records: records, nextCursor: nextCursor)
    }

    private static func sessionCursor(
        after record: SessionContextRecord?,
        projectID: ProjectID,
        provider: AgentProvider?, binding: ContextCursorBinding
    ) throws -> ContextPageCursor? {
        guard let session = record?.session else { throw SQLiteContextReadFailure.malformedEntry }
        return try SQLiteContextCursor.encode(
            operation: .listSessions,
            scopeBinding: projectID.rawValue,
            filterBinding: provider?.rawValue ?? "",
            binding: binding,
            position: SQLiteContextCursorPosition(
                timestamp: SQLiteContextTimestamp.microseconds(
                    sinceUnixEpochFor: session.updatedAt),
                identifier: session.id.rawValue))
    }

    private static func entryCursor(
        after entry: ConversationEntry?, projectID: ProjectID, sessionID: SessionID,
        binding: ContextCursorBinding
    ) throws -> ContextPageCursor? {
        guard let entry else { throw SQLiteContextReadFailure.malformedEntry }
        return try SQLiteContextCursor.encode(
            operation: .loadConversationEntries,
            scopeBinding: conversationScopeBinding(projectID: projectID, sessionID: sessionID),
            filterBinding: "",
            binding: binding,
            position: SQLiteContextCursorPosition(
                timestamp: SQLiteContextTimestamp.microseconds(
                    sinceUnixEpochFor: entry.timestamp),
                identifier: entry.orderingIdentifier))
    }

    private static func sessionRecord(
        from row: [String: SQLiteValue]
    ) throws -> SessionContextRecord {
        guard let sessionID = row["session_id"]?.text.flatMap(SessionID.init(rawValue:)),
            let projectID = row["project_id"]?.text.flatMap(ProjectID.init(rawValue:)),
            let provider = row["provider"]?.text.flatMap(AgentProvider.init(rawValue:)),
            let startedAt = row["started_at"]?.integer,
            let updatedAt = row["updated_at"]?.integer,
            let messageCount = row["message_count"]?.integer, messageCount >= 0,
            let toolCount = row["tool_count"]?.integer, toolCount >= 0
        else { throw SQLiteContextReadFailure.malformedSession }

        let parentSessionID: SessionID?
        if let parentIdentifier = row["parent_session_id"]?.text {
            guard let parsedParentSessionID = SessionID(rawValue: parentIdentifier) else {
                throw SQLiteContextReadFailure.malformedSession
            }
            parentSessionID = parsedParentSessionID
        } else {
            parentSessionID = nil
        }

        return SessionContextRecord(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: provider,
                startedAt: SQLiteContextTimestamp.date(fromUnixMicroseconds: startedAt),
                updatedAt: SQLiteContextTimestamp.date(fromUnixMicroseconds: updatedAt),
                parentSessionID: parentSessionID), messageCount: Int(messageCount),
            toolActivityCount: Int(toolCount))
    }

    static func conversationEntry(
        from row: [String: SQLiteValue]
    ) throws -> ConversationEntry {
        guard let entryKind = row["entry_kind"]?.text,
            let sessionID = row["session_id"]?.text.flatMap(SessionID.init(rawValue:)),
            let identifier = row["entry_id"]?.text,
            let roleOrTool = row["role_or_tool"]?.text,
            let body = row["body"]?.text,
            let recordedAt = row["recorded_at"]?.integer
        else { throw SQLiteContextReadFailure.malformedEntry }
        let timestamp = SQLiteContextTimestamp.date(fromUnixMicroseconds: recordedAt)

        guard entryKind == "message" else {
            guard entryKind == "toolActivity" else { throw SQLiteContextReadFailure.malformedEntry }
            return try toolActivity(
                identifier: identifier, sessionID: sessionID, toolName: roleOrTool,
                invocation: body, outcome: row["outcome"]?.text,
                failedInteger: row["failed"]?.integer, timestamp: timestamp)
        }
        guard let messageID = MessageID(rawValue: identifier),
            let role = ConversationRole(rawValue: roleOrTool)
        else { throw SQLiteContextReadFailure.malformedEntry }
        return .message(
            ConversationMessage(
                id: messageID, sessionID: sessionID, role: role,
                content: body, timestamp: timestamp))
    }

    private static func toolActivity(
        identifier: String,
        sessionID: SessionID,
        toolName: String,
        invocation: String,
        outcome: String?,
        failedInteger: Int64?,
        timestamp: Date
    ) throws -> ConversationEntry {
        guard let activityID = ToolActivityID(rawValue: identifier),
            let failedInteger,
            failedInteger == 0 || failedInteger == 1
        else { throw SQLiteContextReadFailure.malformedEntry }
        return .toolActivity(
            ToolActivity(
                id: activityID, sessionID: sessionID, toolName: toolName,
                invocation: invocation, outcome: outcome, failed: failedInteger == 1,
                timestamp: timestamp))
    }

    private static func conversationScopeBinding(
        projectID: ProjectID, sessionID: SessionID
    ) -> String {
        "\(projectID.rawValue):\(sessionID.rawValue)"
    }
}
