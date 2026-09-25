import AnchorApplication
import AnchorDomain
import Foundation
import MCP
import Testing

@testable import AnchorMCPServerCore

@Test("each tool dispatches to its matching context query")
func routerDispatchesEightQueries() async throws {
    let fixture = RouterFixture()
    let router = AnchorMCPToolRouter(actions: fixture.actions)
    let calls: [(String, [String: Value], String, String)] = [
        ("context.current_project", [:], "project_id", "project"),
        ("context.resume", [:], "project", "sessions"),
        ("context.search", ["text": .string("needle")], "hits", "search"),
        ("context.list_artifacts", [:], "artifacts", "artifacts"),
        (
            "context.get_artifact", ["artifact_id": .string(fixture.artifact.id.rawValue)], "text",
            "artifact"
        ),
        ("context.list_sessions", [:], "sessions", "sessions"),
        (
            "context.get_session", ["session_id": .string(fixture.session.id.rawValue)],
            "message_count", "session"
        ),
        (
            "context.get_messages", ["session_id": .string(fixture.session.id.rawValue)], "entries",
            "messages"
        ),
    ]
    for (name, arguments, expectedKey, expectedOperation) in calls {
        let before = await fixture.operations
        let response = try await router.call(.init(name: name, arguments: arguments))
        #expect(response.isError == false)
        #expect(response.structuredContent?.objectValue?[expectedKey] != nil)
        let after = await fixture.operations
        let newOperations = Array(after.dropFirst(before.count))
        #expect(newOperations.last == expectedOperation)
        #expect(
            newOperations.filter { $0 != "project" }
                == (expectedOperation == "project" ? [] : [expectedOperation]))
    }
}

@Test("router rejects undocumented arguments and unknown tools")
func routerRejectsMalformedCalls() async throws {
    let router = AnchorMCPToolRouter(actions: RouterFixture().actions)
    for parameters in [
        CallTool.Parameters(name: "context.resume", arguments: ["surprise": .bool(true)]),
        CallTool.Parameters(name: "context.unknown"),
        CallTool.Parameters(name: "context.search", arguments: ["text": .string(" ")]),
        CallTool.Parameters(
            name: "context.search", arguments: ["text": .string("x"), "limit": .int(101)]),
    ] {
        do {
            _ = try await router.call(parameters)
            Issue.record("Expected invalidParams for \(parameters.name)")
        } catch MCPError.invalidParams(_) {
        } catch {
            Issue.record("Expected invalidParams for \(parameters.name), received \(error)")
        }
    }
}

@Test("domain failures have stable codes without leaking internal details")
func routerMapsFailuresSafely() async throws {
    let cases: [(ContextQueryFailure, String)] = [
        (.workspaceNotConfigured, "workspace_not_configured"),
        (.workspaceNotAuthorized, "workspace_not_authorized"),
        (.contextUnavailable, "context_unavailable"),
        (.entityNotFound, "entity_not_found"),
        (.invalidCursor, "invalid_cursor"),
        (.contentIsNotText, "content_not_text"),
        (.readFailed, "read_failed"),
    ]
    for (failure, code) in cases {
        let fixture = RouterFixture(failure: failure)
        let response = try await AnchorMCPToolRouter(actions: fixture.actions).call(
            .init(name: "context.current_project"))
        #expect(response.isError == true)
        #expect(response.structuredContent?.objectValue?["code"] == .string(code))
        #expect(response.structuredContent?.objectValue?["message"]?.stringValue != nil)
        #expect(!String(describing: response).contains("fixture-secret"))
    }
}

@Test("in-memory client initializes, lists tools and calls the server")
func serverServesToolsOverInMemoryTransport() async throws {
    let fixture = RouterFixture()
    let server = AnchorMCPServer(actions: fixture.actions)
    let transports = await InMemoryTransport.createConnectedPair()
    try await server.start(transport: transports.server)
    let client = Client(name: "anchor-test", version: "1.0.0")
    let initialization = try await client.connect(transport: transports.client)
    #expect(initialization.serverInfo.name == "anchor")
    let listed = try await client.listTools()
    #expect(listed.tools.count == 8)
    let call = try await client.callTool(name: "context.current_project")
    #expect(call.isError == false)
    #expect(!call.content.isEmpty)
    await client.disconnect()
    await server.waitUntilCompleted()
}

actor RouterFixture: AuthorizedProjectContextReading, ContextAvailabilityReading,
    ProjectContextSearching, ArtifactContextReading, ArtifactRevisionContentReading,
    SessionContextReading, ProjectConversationReading
{
    nonisolated let project: ProjectContext
    nonisolated let artifact: Artifact
    nonisolated let revision: ArtifactRevision
    nonisolated let session: AgentSession
    private let failure: ContextQueryFailure?
    private let includesSession: Bool
    private let messageContent: String
    private let toolName: String
    private let invocation: String
    private let outcome: String?
    private let searchExcerpt: String?
    private(set) var operations: [String] = []

    init(
        failure: ContextQueryFailure? = nil, includesSession: Bool = true,
        messageContent: String = "fixture-secret long message",
        toolName: String = "read", invocation: String = "fixture-secret invocation",
        outcome: String? = nil, projectName: String = "Example",
        workspacePath: String = "/example", canonicalRemote: String? = nil,
        artifactName: String = "notes.md", searchExcerpt: String? = nil
    ) {
        let projectID = ProjectID()
        project = ProjectContext(
            projectID: projectID, displayName: projectName,
            canonicalRepositoryRemote: canonicalRemote.flatMap(
                CanonicalRepositoryRemote.init(rawValue:)),
            workspaceURL: URL(filePath: workspacePath))
        artifact = Artifact(
            id: ArtifactID(), projectID: projectID, provider: .codex, name: artifactName)!
        revision = ArtifactRevision(
            id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
            contentHash: ContentHash.digest(of: Data("fixture-secret".utf8)), deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: 10))!
        session = AgentSession(
            id: SessionID(), projectID: projectID, provider: .codex,
            startedAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 20))
        self.failure = failure
        self.includesSession = includesSession
        self.messageContent = messageContent
        self.toolName = toolName
        self.invocation = invocation
        self.outcome = outcome
        self.searchExcerpt = searchExcerpt
    }

    nonisolated var actions: ContextQueryActions {
        ContextQueryActions(
            currentProject: ResolveCurrentProjectAction(workspace: self, availability: self),
            resume: BuildMinimalProjectResumeAction(
                workspace: self, sessions: self, availability: self),
            search: SearchProjectContextAction(workspace: self, search: self, availability: self),
            listArtifacts: ListProjectArtifactsAction(
                workspace: self, artifacts: self, availability: self),
            readArtifact: ReadProjectArtifactAction(
                workspace: self, artifacts: self, content: self, availability: self),
            listSessions: ListProjectSessionsAction(
                workspace: self, sessions: self, availability: self),
            readSession: ReadProjectSessionAction(
                workspace: self, sessions: self, availability: self),
            readMessages: ReadSessionMessagesAction(
                workspace: self, entries: self, availability: self))
    }

    func loadAvailableGeneration() async throws -> ContextReadGeneration {
        if let failure { throw failure }
        return ContextReadGeneration(
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    }
    func loadAuthorizedProjectContext() async throws -> ProjectContext {
        operations.append("project")
        return project
    }
    func searchContext(
        forProject projectID: ProjectID, matching text: String, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<ProjectContextSearchHit>
    {
        operations.append("search")
        guard let searchExcerpt else { return ContextPage(records: [], nextCursor: nil) }
        return ContextPage(
            records: [
                ProjectContextSearchHit(
                    sessionID: session.id, provider: .codex, kind: .message(.user),
                    excerpt: searchExcerpt, timestamp: Date(timeIntervalSince1970: 12))
            ], nextCursor: nil)
    }
    func listArtifacts(
        forProject projectID: ProjectID, provider: AgentProvider?, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<ArtifactContextRecord>
    {
        operations.append("artifacts")
        return ContextPage(
            records: [ArtifactContextRecord(artifact: artifact, latestRevision: revision)!],
            nextCursor: nil)
    }
    func loadArtifact(withIdentifier artifactID: ArtifactID) async throws -> ArtifactContextRecord?
    {
        operations.append("artifact")
        return ArtifactContextRecord(artifact: artifact, latestRevision: revision)
    }
    func loadRevision(withIdentifier revisionID: RevisionID) async throws -> ArtifactRevision? {
        revision
    }
    func readContent(forRevision revisionID: RevisionID) async throws -> Data? {
        Data("fixture-secret".utf8)
    }
    func listSessions(
        forProject projectID: ProjectID, provider: AgentProvider?, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<SessionContextRecord>
    {
        operations.append("sessions")
        return ContextPage(
            records: includesSession ? [SessionContextRecord(session: session)] : [],
            nextCursor: nil)
    }
    func loadSession(withIdentifier sessionID: SessionID) async throws -> SessionContextRecord? {
        operations.append("session")
        return SessionContextRecord(session: session, messageCount: 1, toolActivityCount: 1)
    }
    func loadConversationEntries(
        inSession sessionID: SessionID, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<ConversationEntry>
    {
        return try await loadConversationEntries(
            inSession: sessionID, forProject: project.projectID, page: page,
            binding: binding)
    }
    func loadConversationEntries(
        inSession sessionID: SessionID, forProject projectID: ProjectID,
        page: ContextPageRequest, binding: ContextCursorBinding
    ) async throws -> ContextPage<ConversationEntry> {
        operations.append("messages")
        return ContextPage(
            records: [
                .message(
                    ConversationMessage(
                        id: MessageID(), sessionID: session.id, role: .user,
                        content: messageContent,
                        timestamp: Date(timeIntervalSince1970: 12))),
                .toolActivity(
                    ToolActivity(
                        id: ToolActivityID(), sessionID: session.id, toolName: toolName,
                        invocation: invocation, outcome: outcome, failed: false,
                        timestamp: Date(timeIntervalSince1970: 13))),
            ], nextCursor: nil)
    }
}
