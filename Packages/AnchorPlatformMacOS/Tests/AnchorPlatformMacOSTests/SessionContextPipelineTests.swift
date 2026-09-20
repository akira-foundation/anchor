import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import AnchorSearch
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("A recorded session, all the way to something that can be asked about")
struct SessionContextPipelineTests {
    private let projectID = ProjectID()
    private let sessionID = SessionID()
    private let recordedAt = Date(timeIntervalSince1970: 1_000)

    private func makeTranscript(_ contents: [String]) -> AgentTranscript {
        AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: recordedAt, updatedAt: recordedAt),
            entries: contents.enumerated().map { offset, content in
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: sessionID,
                        role: offset.isMultiple(of: 2) ? .user : .assistant,
                        content: content, timestamp: recordedAt.addingTimeInterval(Double(offset))))
            })
    }

    private func makeRequest(for transcript: AgentTranscript) throws -> RecordSessionContextRequest
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let content = try encoder.encode(transcript.inConversationOrder)
        let name = AgentSessionArtifactNaming.name(forSession: sessionID, provider: .claude)
        let artifact = try #require(
            Artifact(
                id: ArtifactID.derived(projectID: projectID, provider: .claude, name: name),
                projectID: projectID, provider: .claude, name: name, retention: .latestRevisionOnly)
        )

        return RecordSessionContextRequest(
            artifact: artifact, content: content, contentHash: ContentHash.digest(of: content),
            recordedAt: recordedAt)
    }

    private func makePipeline() async throws -> (
        action: RecordSessionContextAction, search: SQLiteContextSearch, store: SQLiteKnowledgeStore
    ) {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let store = try await SQLiteKnowledgeStore(database: database)
        return (
            RecordSessionContextAction(
                index: SearchedTranscriptIndex(search: search),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(), store: store)),
            search, store
        )
    }

    @Test("a session that was recorded can be found by what was said in it")
    func sessionThatWasRecordedCanBeFoundByWhatWasSaidInIt() async throws {
        let pipeline = try await makePipeline()
        _ = try await pipeline.action.perform(
            try makeRequest(for: makeTranscript(["the checkpoint must not outrun the recording"])))
        #expect(
            try await pipeline.search.findContext(matching: "checkpoint", limit: 10).map(
                \.sessionID) == [sessionID])
    }

    @Test("recording the same session twice does not find it twice")
    func recordingSameSessionTwiceDoesNotFindItTwice() async throws {
        let pipeline = try await makePipeline()
        let request = try makeRequest(
            for: makeTranscript(["the checkpoint must not outrun the recording"]))
        _ = try await pipeline.action.perform(request)
        _ = try await pipeline.action.perform(request)
        #expect(try await pipeline.search.findContext(matching: "checkpoint", limit: 10).count == 1)
    }

    @Test("a marked line in a session becomes something the project knows")
    func markedLineInSessionBecomesSomethingProjectKnows() async throws {
        let pipeline = try await makePipeline()
        _ = try await pipeline.action.perform(
            try makeRequest(
                for: makeTranscript([
                    "DECISION: keep the operation journal local",
                    "TODO: wire the search into the engine",
                    "nothing marked here",
                ])))
        let known = try await pipeline.store.entries(
            forProject: projectID, includingSuperseded: false)
        #expect(known.count == 2)
        #expect(Set(known.map(\.kind)) == [.decision, .todo])
        #expect(known.allSatisfy { $0.source == .session(sessionID) })
    }

    @Test("a marker that was taken out of the session stops being known")
    func markerThatWasTakenOutOfSessionStopsBeingKnown() async throws {
        let pipeline = try await makePipeline()
        let before = makeTranscript([
            "DECISION: keep the operation journal local", "TODO: wire the search",
        ])
        _ = try await pipeline.action.perform(try makeRequest(for: before))
        _ = try await pipeline.action.perform(
            try makeRequest(
                for: AgentTranscript(
                    session: before.session, entries: Array(before.entries.prefix(1)))))
        #expect(
            try await pipeline.store.entries(forProject: projectID, includingSuperseded: false).map(
                \.kind) == [.decision])
    }

    @Test("what a session recorded of its tools is searchable too")
    func whatSessionRecordedOfItsToolsIsSearchableToo() async throws {
        let pipeline = try await makePipeline()
        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude, startedAt: recordedAt,
                updatedAt: recordedAt),
            entries: [
                .toolActivity(
                    ToolActivity(
                        id: ToolActivityID(), sessionID: sessionID, toolName: "Bash",
                        invocation: "xcodebuild -scheme AnchorMac", outcome: "BUILD SUCCEEDED",
                        failed: false,
                        timestamp: recordedAt))
            ])
        _ = try await pipeline.action.perform(try makeRequest(for: transcript))
        #expect(
            try await pipeline.search.findContext(matching: "xcodebuild", limit: 10).map(
                \.sessionID) == [sessionID])
    }
}

@Suite("Rebuilding the index from what is on disk")
struct DiscoveredSessionContextRebuilderTests {
    private let projectID = ProjectID()
    private let recordedAt = Date(timeIntervalSince1970: 1_000)

    private func makeSession(_ content: String) throws -> (SessionID, Artifact, Data) {
        let sessionID = SessionID()
        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude, startedAt: recordedAt,
                updatedAt: recordedAt),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: sessionID, role: .user, content: content,
                        timestamp: recordedAt))
            ])
        let made = try #require(SessionArtifact.make(from: transcript, forProject: projectID))
        return (sessionID, made.artifact, made.content)
    }

    private func makeRebuilder(
        _ database: SQLiteDatabase, _ search: SQLiteContextSearch
    ) async throws -> DiscoveredSessionContextRebuilder {
        DiscoveredSessionContextRebuilder(
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(search: search),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database))))
    }

    @Test("the sessions found on disk become searchable without any change happening")
    func sessionsFoundOnDiskBecomeSearchableWithoutAnyChangeHappening() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let first = try makeSession("the checkpoint stays honest")
        let second = try makeSession("the journal stays local")
        let rebuilt = await (try await makeRebuilder(database, search)).rebuild(
            from: [(artifact: first.1, content: first.2), (artifact: second.1, content: second.2)],
            at: recordedAt)
        #expect(rebuilt.indexedSessions == 2)
        #expect(rebuilt.refusals.isEmpty)
        #expect(
            try await search.findContext(matching: "checkpoint", limit: 10).map(\.sessionID) == [
                first.0
            ])
        #expect(
            try await search.findContext(matching: "journal", limit: 10).map(\.sessionID) == [
                second.0
            ])
    }

    @Test("a session that cannot be read is counted out rather than stopping the rebuild")
    func sessionThatCannotBeReadIsCountedOutRatherThanStoppingRebuild() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let good = try makeSession("the checkpoint stays honest")
        let broken = try makeSession("unused")
        let rebuilt = await (try await makeRebuilder(database, search)).rebuild(
            from: [
                (artifact: broken.1, content: Data("not a transcript".utf8)),
                (artifact: good.1, content: good.2),
            ], at: recordedAt)
        #expect(rebuilt.indexedSessions == 1)
        #expect(rebuilt.refusals.map(\.artifactName) == [broken.1.name])
        #expect(
            try await search.findContext(matching: "checkpoint", limit: 10).map(\.sessionID) == [
                good.0
            ])
    }

    @Test("what is not a session is not rebuilt")
    func whatIsNotSessionIsNotRebuilt() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let plan = try #require(
            Artifact(
                id: ArtifactID(), projectID: projectID, provider: .superpowers,
                name: "docs/superpowers/plans/00.md"))
        let rebuilt = await (try await makeRebuilder(database, search)).rebuild(
            from: [(artifact: plan, content: Data("a plan".utf8))], at: recordedAt)
        #expect(rebuilt.indexedSessions == 0)
    }
}
