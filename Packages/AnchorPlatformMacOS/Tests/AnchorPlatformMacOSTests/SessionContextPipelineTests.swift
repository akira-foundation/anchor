import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import AnchorSearch
import AnchorStorage
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
                ConversationEntry.message(
                    ConversationMessage(
                        id: MessageID(),
                        sessionID: sessionID,
                        role: offset.isMultiple(of: 2) ? .user : .assistant,
                        content: content,
                        timestamp: recordedAt.addingTimeInterval(Double(offset))
                    ))
            }
        )
    }

    private func makeRequest(
        for transcript: AgentTranscript
    ) throws
        -> RecordSessionContextRequest
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let content = try encoder.encode(transcript.inConversationOrder)
        let artifact = try #require(
            Artifact(
                id: ArtifactID.derived(
                    projectID: projectID, provider: .claude,
                    name: AgentSessionArtifactNaming.name(
                        forSession: sessionID, provider: .claude)),
                projectID: projectID,
                provider: .claude,
                name: AgentSessionArtifactNaming.name(forSession: sessionID, provider: .claude),
                retention: .latestRevisionOnly
            ))

        return RecordSessionContextRequest(
            artifact: artifact, content: content,
            contentHash: ContentHash.digest(of: content), recordedAt: recordedAt)
    }

    private func makePipeline() async throws
        -> (
            action: RecordSessionContextAction, search: SQLiteContextSearch,
            store:
                SQLiteKnowledgeStore
        )
    {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let store = try await SQLiteKnowledgeStore(database: database)

        return (
            RecordSessionContextAction(
                index: SearchedTranscriptIndex(search: search),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(), store: store)
            ),
            search,
            store
        )
    }

    @Test("a session that was recorded can be found by what was said in it")
    func sessionThatWasRecordedCanBeFoundByWhatWasSaidInIt() async throws {
        let pipeline = try await makePipeline()
        let transcript = makeTranscript(["the checkpoint must not outrun the recording"])

        _ = try await pipeline.action.perform(try makeRequest(for: transcript))

        let hits = try await pipeline.search.findContext(matching: "checkpoint", limit: 10)

        #expect(hits.map(\.sessionID) == [sessionID])
    }

    @Test("recording the same session twice does not find it twice")
    func recordingSameSessionTwiceDoesNotFindItTwice() async throws {
        let pipeline = try await makePipeline()
        let transcript = makeTranscript(["the checkpoint must not outrun the recording"])
        let request = try makeRequest(for: transcript)

        _ = try await pipeline.action.perform(request)
        _ = try await pipeline.action.perform(request)

        let hits = try await pipeline.search.findContext(matching: "checkpoint", limit: 10)

        #expect(hits.count == 1)
    }

    @Test("a marked line in a session becomes something the project knows")
    func markedLineInSessionBecomesSomethingProjectKnows() async throws {
        let pipeline = try await makePipeline()
        let transcript = makeTranscript([
            "DECISION: keep the operation journal local",
            "TODO: wire the search into the engine",
            "nothing marked here",
        ])

        _ = try await pipeline.action.perform(try makeRequest(for: transcript))

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

        let after = AgentTranscript(
            session: before.session, entries: Array(before.entries.prefix(1)))

        _ = try await pipeline.action.perform(try makeRequest(for: after))

        let known = try await pipeline.store.entries(
            forProject: projectID, includingSuperseded: false)

        #expect(known.map(\.kind) == [.decision])
    }

    @Test("what a session recorded of its tools is searchable too")
    func whatSessionRecordedOfItsToolsIsSearchableToo() async throws {
        let pipeline = try await makePipeline()
        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: recordedAt, updatedAt: recordedAt),
            entries: [
                .toolActivity(
                    ToolActivity(
                        id: ToolActivityID(),
                        sessionID: sessionID,
                        toolName: "Bash",
                        invocation: "xcodebuild -scheme AnchorMac",
                        outcome: "BUILD SUCCEEDED",
                        failed: false,
                        timestamp: recordedAt
                    ))
            ]
        )

        _ = try await pipeline.action.perform(try makeRequest(for: transcript))

        let hits = try await pipeline.search.findContext(matching: "xcodebuild", limit: 10)

        #expect(hits.map(\.sessionID) == [sessionID])
    }
}

@Suite("Which recorded revisions reach the index")
struct StoredSessionContextRecorderTests {
    private let projectID = ProjectID()
    private let recordedAt = Date(timeIntervalSince1970: 1_000)

    private func makeTranscript(_ sessionID: SessionID, _ content: String) -> AgentTranscript {
        AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: recordedAt, updatedAt: recordedAt),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: sessionID, role: .user,
                        content: content, timestamp: recordedAt))
            ]
        )
    }

    private func encode(_ transcript: AgentTranscript) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(transcript.inConversationOrder)
    }

    private func makeArtifact(named name: String, provider: AgentProvider) throws -> Artifact {
        try #require(
            Artifact(id: ArtifactID(), projectID: projectID, provider: provider, name: name))
    }

    @Test("only the sessions among the recorded revisions are indexed")
    func onlySessionsAmongRecordedRevisionsAreIndexed() async throws {
        let storage = InMemoryStorageProvider()
        let contentStore = StoredArtifactContentStore(storage: storage)
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let sessionID = SessionID()

        let sessionRevisionID = RevisionID()
        let planRevisionID = RevisionID()
        let sessionContent = try encode(makeTranscript(sessionID, "the checkpoint stays honest"))
        try await contentStore.storeContent(sessionContent, forRevision: sessionRevisionID)
        try await contentStore.storeContent(
            Data("a plan, not a transcript".utf8), forRevision: planRevisionID)

        let recorder = StoredSessionContextRecorder(
            contentStore: contentStore,
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(search: search),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database)
                )
            )
        )

        let refusals = await recorder.recordSessionContext(
            in: [
                RecordedArtifactRevision(
                    artifact: try makeArtifact(
                        named: "docs/superpowers/plans/00.md", provider: .superpowers),
                    revisionID: planRevisionID,
                    contentHash: ContentHash.digest(of: Data("a plan, not a transcript".utf8))
                ),
                RecordedArtifactRevision(
                    artifact: try makeArtifact(
                        named: AgentSessionArtifactNaming.name(
                            forSession: sessionID, provider: .claude),
                        provider: .claude
                    ),
                    revisionID: sessionRevisionID,
                    contentHash: ContentHash.digest(of: sessionContent)
                ),
            ],
            at: recordedAt
        )

        let hits = try await search.findContext(matching: "checkpoint", limit: 10)

        #expect(refusals.isEmpty)
        #expect(hits.map(\.sessionID) == [sessionID])
    }

    @Test("a session nobody can read does not stop the sessions after it")
    func sessionNobodyCanReadDoesNotStopSessionsAfterIt() async throws {
        let storage = InMemoryStorageProvider()
        let contentStore = StoredArtifactContentStore(storage: storage)
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let goodSessionID = SessionID()

        let brokenRevisionID = RevisionID()
        let goodRevisionID = RevisionID()
        let broken = Data("this was never a transcript".utf8)
        let good = try encode(makeTranscript(goodSessionID, "the checkpoint stays honest"))
        try await contentStore.storeContent(broken, forRevision: brokenRevisionID)
        try await contentStore.storeContent(good, forRevision: goodRevisionID)

        let recorder = StoredSessionContextRecorder(
            contentStore: contentStore,
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(search: search),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database)
                )
            )
        )

        let refusals = await recorder.recordSessionContext(
            in: [
                RecordedArtifactRevision(
                    artifact: try makeArtifact(
                        named: AgentSessionArtifactNaming.name(
                            forSession: SessionID(), provider: .claude),
                        provider: .claude
                    ),
                    revisionID: brokenRevisionID,
                    contentHash: ContentHash.digest(of: broken)
                ),
                RecordedArtifactRevision(
                    artifact: try makeArtifact(
                        named: AgentSessionArtifactNaming.name(
                            forSession: goodSessionID, provider: .claude),
                        provider: .claude
                    ),
                    revisionID: goodRevisionID,
                    contentHash: ContentHash.digest(of: good)
                ),
            ],
            at: recordedAt
        )

        let hits = try await search.findContext(matching: "checkpoint", limit: 10)

        #expect(refusals.count == 1)
        #expect(refusals.first?.description.contains("contentIsNotATranscript") == true)
        #expect(hits.map(\.sessionID) == [goodSessionID])
    }

    @Test("a session whose content is gone is skipped rather than failing the batch")
    func sessionWhoseContentIsGoneIsSkippedRatherThanFailingBatch() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let recorder = StoredSessionContextRecorder(
            contentStore: StoredArtifactContentStore(storage: InMemoryStorageProvider()),
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(
                    search: try await SQLiteContextSearch(database: database)),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database)
                )
            )
        )

        let refusals = await recorder.recordSessionContext(
            in: [
                RecordedArtifactRevision(
                    artifact: try makeArtifact(
                        named: AgentSessionArtifactNaming.name(
                            forSession: SessionID(), provider: .claude),
                        provider: .claude
                    ),
                    revisionID: RevisionID(),
                    contentHash: ContentHash.digest(of: Data())
                )
            ],
            at: recordedAt
        )

        #expect(refusals.isEmpty)
    }
}

@Suite("Rebuilding the index from what is on disk")
struct DiscoveredSessionContextRebuilderTests {
    private let projectID = ProjectID()
    private let recordedAt = Date(timeIntervalSince1970: 1_000)

    private func makeSession(
        _ content: String
    ) throws
        -> (sessionID: SessionID, artifact: Artifact, content: Data)
    {
        let sessionID = SessionID()
        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .claude,
                startedAt: recordedAt, updatedAt: recordedAt),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: sessionID, role: .user,
                        content: content, timestamp: recordedAt))
            ]
        )
        let made = try #require(SessionArtifact.make(from: transcript, forProject: projectID))

        return (sessionID, made.artifact, made.content)
    }

    @Test("the sessions found on disk become searchable without any change happening")
    func sessionsFoundOnDiskBecomeSearchableWithoutAnyChangeHappening() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let rebuilder = DiscoveredSessionContextRebuilder(
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(search: search),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database)
                )
            ))
        let first = try makeSession("the checkpoint stays honest")
        let second = try makeSession("the journal stays local")

        let rebuilt = await rebuilder.rebuild(
            from: [
                (artifact: first.artifact, content: first.content),
                (artifact: second.artifact, content: second.content),
            ],
            at: recordedAt
        )

        #expect(rebuilt.indexedSessions == 2)
        #expect(rebuilt.refusals.isEmpty)
        #expect(
            try await search.findContext(matching: "checkpoint", limit: 10).map(\.sessionID)
                == [first.sessionID])
        #expect(
            try await search.findContext(matching: "journal", limit: 10).map(\.sessionID)
                == [second.sessionID])
    }

    @Test("a session that cannot be read is counted out rather than stopping the rebuild")
    func sessionThatCannotBeReadIsCountedOutRatherThanStoppingRebuild() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let rebuilder = DiscoveredSessionContextRebuilder(
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(search: search),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database)
                )
            ))
        let good = try makeSession("the checkpoint stays honest")
        let broken = try makeSession("unused")

        let rebuilt = await rebuilder.rebuild(
            from: [
                (artifact: broken.artifact, content: Data("not a transcript".utf8)),
                (artifact: good.artifact, content: good.content),
            ],
            at: recordedAt
        )

        #expect(rebuilt.indexedSessions == 1)
        #expect(rebuilt.refusals.map(\.artifactName) == [broken.artifact.name])
        #expect(
            try await search.findContext(matching: "checkpoint", limit: 10).map(\.sessionID)
                == [good.sessionID])
    }

    @Test("what is not a session is not rebuilt")
    func whatIsNotSessionIsNotRebuilt() async throws {
        let database = try SQLiteDatabase(fileURL: nil)
        let rebuilder = DiscoveredSessionContextRebuilder(
            action: RecordSessionContextAction(
                index: SearchedTranscriptIndex(
                    search: try await SQLiteContextSearch(database: database)),
                knowledge: ExtractedSessionKnowledge(
                    extractor: MarkedKnowledgeExtractor(),
                    store: try await SQLiteKnowledgeStore(database: database)
                )
            ))
        let plan = try #require(
            Artifact(
                id: ArtifactID(), projectID: projectID, provider: .superpowers,
                name: "docs/superpowers/plans/00.md"))

        let rebuilt = await rebuilder.rebuild(
            from: [(artifact: plan, content: Data("a plan".utf8))], at: recordedAt)

        #expect(rebuilt.indexedSessions == 0)
    }
}
