import AnchorApplication
import AnchorDomain
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
        #expect(artifacts.nextCursor == nil)
        let artifact = try #require(artifacts.records.first)
        #expect(artifact.artifact.name == "stdio-plan.md")
        let sessions = try await reader.listSessions.perform(
            try #require(ListProjectSessionsRequest(limit: 1)))
        #expect(sessions.records.count == 1)
        #expect(sessions.nextCursor == nil)
        let session = try #require(sessions.records.first)
        #expect(session.session.provider == .claude)
        let metadata = try await reader.readSession.perform(
            ReadProjectSessionRequest(sessionID: session.session.id))
        #expect(metadata.messageCount == 1)
        #expect(metadata.toolActivityCount == 1)
        let entries = try await reader.readMessages.perform(
            try #require(ReadSessionMessagesRequest(sessionID: session.session.id)))
        try #require(entries.records.count == 2)
        guard case .message(let message) = entries.records[0],
            case .toolActivity(let activity) = entries.records[1]
        else {
            Issue.record("Fixture must contain a message followed by tool activity")
            return
        }
        #expect(message.role == .user)
        #expect(message.content == "stdio checkpoint ready API_KEY=[redacted:assigned-secret]")
        #expect(activity.toolName == "read")
        #expect(activity.invocation == "inspect stdio-plan.md")
        let search = try await reader.search.perform(
            try #require(SearchProjectContextRequest(text: "checkpoint", limit: 1)))
        #expect(search.records.count == 1)
        #expect(search.nextCursor == nil)
        #expect(search.records.first?.sessionID == session.session.id)
        let resume = try await reader.resume.perform(ProjectContextRequest())
        #expect(resume.project.projectID == project.projectID)
        #expect(resume.latestSession?.id == session.session.id)
        await #expect(throws: ContextQueryFailure.contextUnavailable) {
            try await reader.readArtifact.perform(
                try #require(ReadProjectArtifactRequest(artifactID: artifact.artifact.id)))
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.supportURL.appending(path: "storage").path()))
    }
}

private struct MCPStdioFixture {
    let supportURL: URL
    let workspaceURL: URL
    let ownsDirectory: Bool

    static func create() async throws -> MCPStdioFixture {
        let outputPath = ProcessInfo.processInfo.environment["ANCHOR_MCP_FIXTURE_OUTPUT"]
        let supportURL =
            outputPath.map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory.appending(path: "anchor-stdio-\(UUID())")
        let fixture = MCPStdioFixture(
            supportURL: supportURL, workspaceURL: supportURL.appending(path: "workspace"),
            ownsDirectory: outputPath == nil)
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
        try await ContextReadModelAssembly.openReader(
            requestedWorkspacePath: workspaceURL.path(), supportDirectoryURL: supportURL,
            configurationURL: ObservedWorkspaceConfiguration.defaultFileURL(
                inSupportDirectoryAt: supportURL), keyLoader: { nil })
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
        let artifact = try #require(
            Artifact(
                id: ArtifactID.derived(fromSeed: "stdio-artifact"),
                projectID: writer.observedWorkspace.projectID, provider: .claude,
                name: "stdio-plan.md"))
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID.derived(fromSeed: "stdio-revision"), artifactID: artifact.id,
                parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("metadata only".utf8)),
                deviceID: DeviceID.derived(fromSeed: "stdio-device"),
                createdAt: Date(timeIntervalSince1970: 10)))
        try await writer.artifacts.indexArtifactRevisions([
            RecordedArtifactRevision(artifact: artifact, revision: revision)
        ])
        let sessionID = SessionID.derived(fromSeed: "stdio-session")
        let transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: writer.observedWorkspace.projectID, provider: .claude,
                startedAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 30)),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID.derived(fromSeed: "stdio-message"), sessionID: sessionID,
                        role: .user,
                        content: SessionSecretRedactor().redact(
                            "stdio checkpoint ready API_KEY=anchor-stdio-raw-secret-0123456789"),
                        timestamp: Date(timeIntervalSince1970: 20))),
                .toolActivity(
                    ToolActivity(
                        id: ToolActivityID.derived(fromSeed: "stdio-activity"),
                        sessionID: sessionID,
                        toolName: "read", invocation: "inspect stdio-plan.md", outcome: nil,
                        failed: false, timestamp: Date(timeIntervalSince1970: 30))),
            ])
        try await SQLiteContextSearch(database: writer.database).indexTranscript(transcript)
        try await writer.status.completeUpdate(update, succeeded: true)
    }
}

private struct FixtureRepositoryRemote: RepositoryRemoteReading {
    func readRepositoryRemote(atDirectory directoryURL: URL) async throws -> RepositoryRemoteOutcome
    {
        .repositoryWithoutRemote
    }
}
