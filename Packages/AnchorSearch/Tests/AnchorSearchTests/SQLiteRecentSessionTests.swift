import AnchorApplication
import AnchorDomain
import AnchorPersistence
import AnchorSearch
import Foundation
import Testing

@Suite("SQLite recent session selection")
struct SQLiteRecentSessionTests {
    @Test("the newest project session uses a stable tie break and preserves entry counts")
    func mostRecentSessionIsProjectScopedAndCounted() async throws {
        let projectID = ProjectID.derived(fromSeed: "recent-session-project")
        let otherProjectID = ProjectID.derived(fromSeed: "other-session-project")
        let tiedSessionIDs = [
            SessionID.derived(fromSeed: "tie-z"),
            SessionID.derived(fromSeed: "tie-a"),
        ].sorted { $0.rawValue < $1.rawValue }
        let selectedSessionID = tiedSessionIDs[0]
        let search = try await SQLiteContextSearch(database: SQLiteDatabase(fileURL: nil))

        try await search.indexTranscript(
            transcript(
                sessionID: SessionID.derived(fromSeed: "older"), projectID: projectID,
                updatedAt: 100, messageCount: 1, toolCount: 0))
        try await search.indexTranscript(
            transcript(
                sessionID: tiedSessionIDs[1], projectID: projectID,
                updatedAt: 200, messageCount: 0, toolCount: 0))
        try await search.indexTranscript(
            transcript(
                sessionID: selectedSessionID, projectID: projectID,
                updatedAt: 200, messageCount: 2, toolCount: 1))
        try await search.indexTranscript(
            transcript(
                sessionID: SessionID.derived(fromSeed: "foreign-newest"),
                projectID: otherProjectID, updatedAt: 300, messageCount: 3, toolCount: 2))

        let selected = try #require(try await search.loadMostRecentSession(forProject: projectID))

        #expect(selected.session.id == selectedSessionID)
        #expect(selected.session.updatedAt == Date(timeIntervalSince1970: 200))
        #expect(selected.messageCount == 2)
        #expect(selected.toolActivityCount == 1)
        #expect(try await search.loadMostRecentSession(forProject: ProjectID()) == nil)
    }

    private func transcript(
        sessionID: SessionID, projectID: ProjectID, updatedAt: TimeInterval,
        messageCount: Int, toolCount: Int
    ) -> AgentTranscript {
        let session = AgentSession(
            id: sessionID, projectID: projectID, provider: .codex,
            startedAt: Date(timeIntervalSince1970: updatedAt - 10),
            updatedAt: Date(timeIntervalSince1970: updatedAt))
        let messages: [ConversationEntry] = (0..<messageCount).map { offset in
            .message(
                ConversationMessage(
                    id: MessageID.derived(fromSeed: "\(sessionID.rawValue)-message-\(offset)"),
                    sessionID: sessionID, role: .user, content: "message \(offset)",
                    timestamp: Date(timeIntervalSince1970: updatedAt - 1)))
        }
        let tools: [ConversationEntry] = (0..<toolCount).map { offset in
            .toolActivity(
                ToolActivity(
                    id: ToolActivityID.derived(
                        fromSeed: "\(sessionID.rawValue)-tool-\(offset)"),
                    sessionID: sessionID, toolName: "tool", invocation: "invocation",
                    outcome: nil, failed: false,
                    timestamp: Date(timeIntervalSince1970: updatedAt - 1)))
        }
        return AgentTranscript(session: session, entries: messages + tools)
    }
}
