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

    private func message(_ text: String, role: ConversationRole = .user) -> ConversationEntry {
        .message(
            ConversationMessage(
                id: MessageID(), sessionID: sessionID, role: role, content: text,
                timestamp: Date(timeIntervalSince1970: 100)
            )
        )
    }

    private func activity(
        tool: String, invocation: String, outcome: String?
    ) -> ConversationEntry {
        .toolActivity(
            ToolActivity(
                id: ToolActivityID(), sessionID: sessionID, toolName: tool,
                invocation: invocation, outcome: outcome, failed: false,
                timestamp: Date(timeIntervalSince1970: 200)
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
}
