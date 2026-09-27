import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPlatformMacOS
import AnchorProvider
import AnchorSearch
import Foundation
import Testing

@Suite("MCP stdio read-model fixture")
struct AnchorMCPStdioFixtureTests {
    @Test("the persisted fixture serves seven queries without an encryption key")
    func fixtureServesMetadataAndRefusesEncryptedContent() async throws {
        let fixture = try await MCPStdioFixture.create()
        defer { fixture.removeOwnedDirectory() }
        let reader = try await fixture.reader()
        let project = try await reader.currentProject.perform(ProjectContextRequest())
        #expect(project.displayName == "anchor-stdio-fixture")
        #expect(
            WorkspacePath.comparable(project.workspaceURL)
                == WorkspacePath.comparable(fixture.workspaceURL))
        let artifacts = try await reader.listArtifacts.perform(
            try #require(ListProjectArtifactsRequest(limit: 1)))
        #expect(artifacts.records.count == 1)
        #expect(artifacts.nextCursor != nil)
        let artifact = try #require(artifacts.records.first)
        #expect(artifact.artifact.name == "stdio-latest-note.md")
        let sessions = try await reader.listSessions.perform(
            try #require(ListProjectSessionsRequest(limit: 1)))
        #expect(sessions.records.count == 1)
        #expect(sessions.nextCursor != nil)
        let session = try #require(sessions.records.first)
        #expect(session.session.provider == .codex)
        let metadata = try await reader.readSession.perform(
            ReadProjectSessionRequest(sessionID: session.session.id))
        #expect(metadata.messageCount == 2)
        #expect(metadata.toolActivityCount == 1)
        let entries = try await reader.readMessages.perform(
            try #require(ReadSessionMessagesRequest(sessionID: session.session.id)))
        try #require(entries.records.count == 3)
        guard case .message(let message) = entries.records[0],
            case .toolActivity(let activity) = entries.records[2]
        else {
            Issue.record("Fixture must contain a message followed by tool activity")
            return
        }
        #expect(message.role == .user)
        #expect(message.content == "stdio checkpoint ready API_KEY=[redacted:assigned-secret]")
        #expect(activity.toolName == "read")
        #expect(activity.invocation == "inspect stdio-latest-note.md")
        let search = try await reader.search.perform(
            try #require(SearchProjectContextRequest(text: "checkpoint", limit: 1)))
        #expect(search.records.count == 1)
        #expect(search.nextCursor == nil)
        #expect(search.records.first?.sessionID == session.session.id)
        let resume = try await reader.resume.perform(ProjectContextRequest())
        #expect(resume.project.projectID == project.projectID)
        #expect(
            resume.recentSession?.session.id
                == SessionID.derived(fromSeed: "stdio-recent-session"))
        #expect(resume.recentSession?.session.provider == .codex)
        #expect(resume.recentSession?.messageCount == 2)
        #expect(resume.recentSession?.toolActivityCount == 1)
        #expect(
            resume.currentPlan?.artifact.id
                == ArtifactID.derived(fromSeed: "stdio-current-plan"))
        #expect(
            resume.latestBrainstorm?.artifact.id
                == ArtifactID.derived(fromSeed: "stdio-brainstorm"))
        #expect(
            resume.relevantGraphs.map(\.artifact.id)
                == (0..<3).map { ArtifactID.derived(fromSeed: "stdio-graph-\($0)") })
        #expect(resume.recentDecisions.count == 5)
        #expect(resume.openTodos.count == 5)
        #expect(resume.openQuestions.count == 5)
        #expect(resume.hasMoreDecisions)
        #expect(resume.hasMoreTodos)
        #expect(resume.hasMoreQuestions)
        #expect(
            resume.recentDecisions.map(\.id)
                == (0..<5).map { KnowledgeEntryID.derived(fromSeed: "stdio-decision-\($0)") })
        #expect(
            resume.openTodos.map(\.id)
                == (0..<5).map { KnowledgeEntryID.derived(fromSeed: "stdio-todo-\($0)") })
        #expect(
            resume.openQuestions.map(\.id)
                == (0..<5).map { KnowledgeEntryID.derived(fromSeed: "stdio-question-\($0)") })
        #expect(resume.recentDecisions.first?.summary.utf8.count == 512)
        #expect(resume.recentDecisions.first?.summaryIsTruncated == true)
        #expect(resume.lastPresence?.deviceID == DeviceID.derived(fromSeed: "stdio-latest-device"))
        #expect(resume.lastActivityAt == Date(timeIntervalSince1970: 110))
        #expect(resume.lastAgentProvider == .codex)
        #expect(await fixture.keyLoads.count == 0)
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.readArtifact.perform(
                try #require(ReadProjectArtifactRequest(artifactID: artifact.artifact.id)))
        }
        #expect(await fixture.keyLoads.count == 1)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.supportURL.appending(path: "storage").path()))
    }
}

struct MCPStdioFixture {
    let supportURL: URL
    let workspaceURL: URL
    let ownsDirectory: Bool
    let keyLoads: FixtureKeyLoadCount

    static func create() async throws -> MCPStdioFixture {
        let outputPath = ProcessInfo.processInfo.environment["ANCHOR_MCP_FIXTURE_OUTPUT"]
        let supportURL =
            outputPath.map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory.appending(path: "anchor-stdio-\(UUID())")
        let fixture = MCPStdioFixture(
            supportURL: supportURL, workspaceURL: supportURL.appending(path: "workspace"),
            ownsDirectory: outputPath == nil, keyLoads: FixtureKeyLoadCount())
        do {
            try await fixture.writeReadModel()
            return fixture
        } catch {
            fixture.removeOwnedDirectory()
            throw error
        }
    }

    func removeOwnedDirectory() {
        guard ownsDirectory else { return }
        try? FileManager.default.removeItem(at: supportURL)
    }

    func reader() async throws -> ContextReadModelReader {
        let keyLoads = keyLoads
        return try await ContextReadModelAssembly.openReader(
            requestedWorkspacePath: workspaceURL.path(), supportDirectoryURL: supportURL,
            configurationURL: ObservedWorkspaceConfiguration.defaultFileURL(
                inSupportDirectoryAt: supportURL),
            keyLoader: {
                await keyLoads.recordLoad()
                return nil
            })
    }

    private func writeReadModel() async throws {
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let configurationURL = ObservedWorkspaceConfiguration.defaultFileURL(
            inSupportDirectoryAt: supportURL)
        try JSONSerialization.data(withJSONObject: [
            "workspacePath": workspaceURL.path(), "projectName": "anchor-stdio-fixture",
        ]).write(to: configurationURL, options: .atomic)
        let writer = try await ContextReadModelAssembly.openWriter(
            supportDirectoryURL: supportURL, configurationURL: configurationURL,
            remoteReader: FixtureRepositoryRemote())
        let update = try await writer.status.beginUpdate(rebuilding: true)
        let projectID = writer.observedWorkspace.projectID
        let otherProjectID = ProjectID.derived(fromSeed: "stdio-foreign-project")
        let graphs = try (0..<4).map { offset in
            try artifactRecord(
                seed: "stdio-graph-\(offset)", projectID: projectID, provider: .graphify,
                name: "graphs/stdio-graph-\(offset).json", revisedAt: 94 - TimeInterval(offset))
        }
        try await writer.artifacts.indexArtifactRevisions(
            [
                try artifactRecord(
                    seed: "stdio-current-plan", projectID: projectID, provider: .superpowers,
                    name: "docs/superpowers/plans/26-context-resume.md", revisedAt: 100),
                try artifactRecord(
                    seed: "stdio-older-plan", projectID: projectID, provider: .superpowers,
                    name: "docs/superpowers/plans/25-old.md", revisedAt: 50),
                try artifactRecord(
                    seed: "stdio-brainstorm", projectID: projectID, provider: .superpowers,
                    name: ".superpowers/brainstorm/context-resume.md", revisedAt: 95),
                try artifactRecord(
                    seed: "stdio-latest-note", projectID: projectID, provider: .claude,
                    name: "stdio-latest-note.md", revisedAt: 110),
                try artifactRecord(
                    seed: "stdio-foreign-plan", projectID: otherProjectID,
                    provider: .superpowers, name: "docs/superpowers/plans/foreign.md",
                    revisedAt: 1_000),
            ] + graphs)

        let sessionID = SessionID.derived(fromSeed: "stdio-recent-session")
        let recentTranscript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: projectID, provider: .codex,
                startedAt: date(70), updatedAt: date(80)),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID.derived(fromSeed: "stdio-message"), sessionID: sessionID,
                        role: .user,
                        content: SessionSecretRedactor().redact(
                            "stdio checkpoint ready API_KEY=anchor-stdio-raw-secret-0123456789"),
                        timestamp: date(75))),
                .message(
                    ConversationMessage(
                        id: MessageID.derived(fromSeed: "stdio-response"), sessionID: sessionID,
                        role: .assistant, content: "fixture ready", timestamp: date(78))),
                .toolActivity(
                    ToolActivity(
                        id: ToolActivityID.derived(fromSeed: "stdio-activity"),
                        sessionID: sessionID, toolName: "read",
                        invocation: "inspect stdio-latest-note.md", outcome: nil,
                        failed: false, timestamp: date(80))),
            ])
        let search = try await SQLiteContextSearch(database: writer.database)
        try await search.indexTranscript(recentTranscript)
        try await search.indexTranscript(
            AgentTranscript(
                session: AgentSession(
                    id: SessionID.derived(fromSeed: "stdio-older-session"),
                    projectID: projectID, provider: .claude, startedAt: date(20),
                    updatedAt: date(30)),
                entries: []))

        let knowledge = try await SQLiteKnowledgeStore(database: writer.database)
        let decisions = (0..<6).map { offset in
            knowledgeEntry(
                seed: "stdio-decision-\(offset)", projectID: projectID, kind: .decision,
                summary: offset == 0 ? String(repeating: "d", count: 600) : nil,
                createdAt: 108 - TimeInterval(offset))
        }
        let todos = (0..<6).map { offset in
            knowledgeEntry(
                seed: "stdio-todo-\(offset)", projectID: projectID, kind: .todo,
                createdAt: 102 - TimeInterval(offset))
        }
        let questions = (0..<6).map { offset in
            knowledgeEntry(
                seed: "stdio-question-\(offset)", projectID: projectID, kind: .question,
                createdAt: 96 - TimeInterval(offset))
        }
        let supersededSource = KnowledgeEntrySource.artifact(
            ArtifactID.derived(fromSeed: "stdio-superseded-source"))
        try await knowledge.recordEntries(
            decisions + todos + questions + [
                knowledgeEntry(
                    seed: "stdio-superseded", projectID: projectID, kind: .decision,
                    createdAt: 1_500, source: supersededSource),
                knowledgeEntry(
                    seed: "stdio-foreign-decision", projectID: otherProjectID,
                    kind: .decision, createdAt: 2_000),
            ],
            supersedingEntriesFrom: .artifact(ArtifactID.derived(fromSeed: "stdio-unused")))
        try await knowledge.recordEntries(
            [
                knowledgeEntry(
                    seed: "stdio-superseding-risk", projectID: projectID, kind: .risk,
                    createdAt: 101, source: supersededSource)
            ], supersedingEntriesFrom: supersededSource)

        try await writer.presences.recordPresence(
            DevicePresence(
                projectID: projectID,
                deviceID: DeviceID.derived(fromSeed: "stdio-older-device"),
                lastSeenAt: date(60)))
        try await writer.presences.recordPresence(
            DevicePresence(
                projectID: projectID,
                deviceID: DeviceID.derived(fromSeed: "stdio-latest-device"),
                lastSeenAt: date(90)))
        try await writer.status.completeUpdate(update, succeeded: true)
    }

}
