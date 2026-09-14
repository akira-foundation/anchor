import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation

@testable import AnchorSearch

func index(_ transcript: AgentTranscript, at databaseFileURL: URL) async throws {
    let search = try await SQLiteContextSearch(
        database: try SQLiteDatabase(fileURL: databaseFileURL))
    try await search.indexTranscript(transcript)
}

func makeDatabaseFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "anchor-session-context-\(UUID().uuidString)/index.sqlite")
}

func makePageRequest(limit: Int, cursor: ContextPageCursor? = nil) -> ContextPageRequest {
    ContextPageRequest(limit: limit, cursor: cursor, maximumLimit: 100)!
}

func makeSession(
    identifierSuffix: Int,
    projectIdentifierSuffix: Int = 9,
    provider: AgentProvider = .claude,
    startedAt: TimeInterval = 10,
    updatedAt: TimeInterval
) -> AgentSession {
    AgentSession(
        id: sessionID(identifierSuffix),
        projectID: projectID(projectIdentifierSuffix),
        provider: provider,
        startedAt: Date(timeIntervalSince1970: startedAt),
        updatedAt: Date(timeIntervalSince1970: updatedAt))
}

func makeMessage(
    sessionID: SessionID,
    identifierSuffix: Int,
    text: String,
    role: ConversationRole = .user,
    at timestamp: TimeInterval
) -> ConversationEntry {
    .message(
        ConversationMessage(
            id: messageID(identifierSuffix), sessionID: sessionID, role: role,
            content: text, timestamp: Date(timeIntervalSince1970: timestamp)))
}

func makeActivity(
    sessionID: SessionID,
    identifierSuffix: Int,
    toolName: String = "Bash",
    invocation: String = "swift test",
    outcome: String? = "passed",
    failed: Bool = false,
    at timestamp: TimeInterval
) -> ConversationEntry {
    .toolActivity(
        ToolActivity(
            id: activityID(identifierSuffix), sessionID: sessionID, toolName: toolName,
            invocation: invocation, outcome: outcome, failed: failed,
            timestamp: Date(timeIntervalSince1970: timestamp)))
}

func entryBody(_ entry: ConversationEntry) -> String {
    switch entry {
    case .message(let message): message.content
    case .toolActivity(let activity): [activity.invocation, activity.outcome ?? ""].joined()
    }
}

func makeCursor(rawJSON: String) -> ContextPageCursor {
    let token = Data(rawJSON.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return ContextPageCursor(rawValue: token)!
}

func projectID(_ suffix: Int = 9) -> ProjectID {
    ProjectID(rawValue: identifierText(suffix: suffix))!
}

func sessionID(_ suffix: Int) -> SessionID {
    SessionID(rawValue: identifierText(suffix: suffix))!
}

func messageID(_ suffix: Int) -> MessageID {
    MessageID(rawValue: identifierText(suffix: suffix))!
}

func activityID(_ suffix: Int) -> ToolActivityID {
    ToolActivityID(rawValue: identifierText(suffix: suffix))!
}

func identifierText(suffix: Int) -> String {
    String(format: "00000000-0000-0000-0000-%012d", suffix)
}
