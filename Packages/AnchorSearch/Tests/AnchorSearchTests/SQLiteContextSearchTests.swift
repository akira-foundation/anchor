import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorSearch

@Suite("Searching the context that reached this machine")
struct SQLiteContextSearchTests {
    private let sessionID = SessionID()
    private let projectID = ProjectID()

    private func makeSearch() async throws -> SQLiteContextSearch {
        try await SQLiteContextSearch(database: try SQLiteDatabase(fileURL: nil))
    }

    private func message(
        _ text: String, id: MessageID = MessageID(), role: ConversationRole = .user
    ) -> ConversationEntry {
        .message(
            ConversationMessage(
                id: id, sessionID: sessionID, role: role, content: text,
                timestamp: Date(timeIntervalSince1970: 100)
            )
        )
    }

    private func activity(
        id: ToolActivityID = ToolActivityID(),
        tool: String,
        invocation: String,
        outcome: String?,
        timestamp: TimeInterval = 200
    ) -> ConversationEntry {
        .toolActivity(
            ToolActivity(
                id: id, sessionID: sessionID, toolName: tool,
                invocation: invocation, outcome: outcome, failed: false,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
        )
    }

    private func transcript(_ entries: [ConversationEntry]) -> AgentTranscript {
        AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 300)
            ),
            entries: entries
        )
    }

    @Test("a word said in a message finds the message")
    func aWordSaidInAMessageFindsTheMessage() async throws {
        let search = try await makeSearch()
        try await search.indexTranscript(
            transcript([message("we decided retention governs the content lifetime")]))

        let hits = try await search.findContext(matching: "retention", limit: 10)

        #expect(hits.count == 1)
        #expect(hits.first?.kind == .message(.user))
        #expect(hits.first?.sessionID == sessionID)
        #expect(hits.first?.excerpt.contains("retention") == true)
    }

    @Test("a word in a command finds the tool and says which one")
    func aWordInACommandFindsTheToolAndSaysWhichOne() async throws {
        let search = try await makeSearch()
        try await search.indexTranscript(
            transcript([
                activity(tool: "Bash", invocation: "swift build --arch arm64", outcome: "ok")
            ]))

        let hits = try await search.findContext(matching: "arm64", limit: 10)

        #expect(hits.first?.kind == .toolActivity("Bash"))
    }

    @Test("what was said and what was run are told apart")
    func whatWasSaidAndWhatWasRunAreToldApart() async throws {
        let search = try await makeSearch()
        try await search.indexTranscript(
            transcript([
                message("run the migration"),
                activity(tool: "Bash", invocation: "swift run migration", outcome: "done"),
            ])
        )

        let kinds = try await search.findContext(matching: "migration", limit: 10).map(\.kind)

        #expect(kinds.contains(.message(.user)))
        #expect(kinds.contains(.toolActivity("Bash")))
    }

    @Test("indexing the same session again does not duplicate it")
    func indexingTheSameSessionAgainDoesNotDuplicateIt() async throws {
        let search = try await makeSearch()
        let indexed = transcript([message("we decided retention governs the lifetime")])

        try await search.indexTranscript(indexed)
        try await search.indexTranscript(indexed)

        #expect(try await search.findContext(matching: "retention", limit: 10).count == 1)
    }

    @Test("every word has to appear, not just one of them")
    func everyWordHasToAppearNotJustOneOfThem() async throws {
        let search = try await makeSearch()
        try await search.indexTranscript(
            transcript([message("retention governs the content"), message("the engine drains")]))

        let hits = try await search.findContext(matching: "retention drains", limit: 10)

        #expect(hits.isEmpty)
    }

    @Test(
        "a query carrying search syntax neither breaks nor changes the question",
        arguments: ["retention*", "retention OR drains", "reten\"tion", "(retention", "NEAR/2"]
    )
    func aQueryCarryingSearchSyntaxNeitherBreaksNorChangesTheQuestion(_ query: String) async throws
    {
        let search = try await makeSearch()
        try await search.indexTranscript(transcript([message("retention governs the content")]))

        let hits = try await search.findContext(matching: query, limit: 10)

        #expect(hits.count <= 1)
    }

    @Test("a query with no words at all finds nothing rather than everything")
    func aQueryWithNoWordsAtAllFindsNothingRatherThanEverything() async throws {
        let search = try await makeSearch()
        try await search.indexTranscript(transcript([message("retention governs the content")]))

        #expect(try await search.findContext(matching: "  ***  ", limit: 10).isEmpty)
    }

    @Test("a masked secret is not findable by the value that was masked")
    func aMaskedSecretIsNotFindableByTheValueThatWasMasked() async throws {
        let search = try await makeSearch()
        try await search.indexTranscript(
            transcript([
                activity(
                    tool: "Bash",
                    invocation: "psql postgresql://appuser:[redacted:url-credentials]@db/anchor",
                    outcome: "connected"
                )
            ])
        )

        #expect(try await search.findContext(matching: "hunter2secret", limit: 10).isEmpty)
        #expect(try await search.findContext(matching: "redacted", limit: 10).count == 1)
    }

    @Test("reindexing replaces tool invocation and outcome search text")
    func reindexingReplacesToolActivitySearchText() async throws {
        let search = try await makeSearch()
        try await search.indexTranscript(
            transcript([
                activity(
                    tool: "Bash", invocation: "obsolete-tool-command",
                    outcome: "obsolete-tool-output")
            ]))

        try await search.indexTranscript(
            transcript([
                activity(
                    tool: "Shell", invocation: "replacement-tool-command",
                    outcome: "replacement-tool-output", timestamp: 400.123456)
            ]))

        let replacementHit = try #require(
            await search.findContext(matching: "replacement-tool-command", limit: 10).first)
        #expect(try await search.findContext(matching: "obsolete-tool-command", limit: 10).isEmpty)
        #expect(try await search.findContext(matching: "obsolete-tool-output", limit: 10).isEmpty)
        #expect(replacementHit.kind == .toolActivity("Shell"))
        #expect(abs(replacementHit.timestamp.timeIntervalSince1970 - 400.123456) < 0.000001)
        #expect(
            try await search.findContext(matching: "replacement-tool-output", limit: 10).count == 1)
    }

    @Test("a failed reindex restores tool activity search rows")
    func failedReindexRestoresToolActivitySearchRows() async throws {
        let search = try await makeSearch()
        let blockingEntryID = MessageID()
        let blockingSessionID = SessionID()
        let blockingSession = AgentSession(
            id: blockingSessionID, projectID: projectID, provider: .claude,
            startedAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 300))
        let blockingEntry = ConversationEntry.message(
            ConversationMessage(
                id: blockingEntryID, sessionID: blockingSessionID, role: .user,
                content: "blocking-message-token", timestamp: Date(timeIntervalSince1970: 100)))
        let collidingActivityID = ToolActivityID(rawValue: blockingEntryID.rawValue)!

        try await search.indexTranscript(
            transcript([
                activity(
                    tool: "Bash", invocation: "durable-tool-command",
                    outcome: "durable-tool-output")
            ]))
        try await search.indexTranscript(
            AgentTranscript(session: blockingSession, entries: [blockingEntry]))

        await #expect(throws: SQLiteDatabase.Failure.self) {
            try await search.indexTranscript(
                transcript([
                    activity(
                        tool: "Shell", invocation: "partial-tool-command",
                        outcome: "partial-tool-output"),
                    activity(
                        id: collidingActivityID, tool: "Shell",
                        invocation: "collision-tool-command", outcome: nil),
                ]))
        }

        #expect(
            try await search.findContext(matching: "durable-tool-command", limit: 10).count == 1)
        #expect(try await search.findContext(matching: "durable-tool-output", limit: 10).count == 1)
        #expect(try await search.findContext(matching: "partial-tool-command", limit: 10).isEmpty)
        #expect(try await search.findContext(matching: "collision-tool-command", limit: 10).isEmpty)
    }
}
