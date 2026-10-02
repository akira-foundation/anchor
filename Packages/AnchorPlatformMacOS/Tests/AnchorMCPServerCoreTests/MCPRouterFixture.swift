import AnchorApplication
import AnchorDomain
import Foundation

@testable import AnchorMCPServerCore

actor RouterFixture: AuthorizedProjectContextReading, ContextAvailabilityReading,
    ProjectContextSearching, ArtifactContextReading, ArtifactRevisionContentReading,
    SessionContextReading, ProjectConversationReading, ProjectResumeReading,
    KnowledgeContextReading
{
    nonisolated let project: ProjectContext
    nonisolated let artifact: Artifact
    nonisolated let revision: ArtifactRevision
    nonisolated let session: AgentSession
    nonisolated let populatedResume: ProjectResume
    nonisolated let knowledgeEntry: KnowledgeEntry
    private let failure: ContextQueryFailure?
    private let includesSession: Bool
    private let messageContent: String
    private let toolName: String
    private let invocation: String
    private let outcome: String?
    private let searchExcerpt: String?
    private(set) var operations: [String] = []
    private(set) var requestedKnowledgeKind: KnowledgeEntryKind?
    private(set) var requestedKnowledgeOrigin: KnowledgeEntryOrigin?
    private(set) var requestedKnowledgeLimit: Int?

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
        let plan = Self.resumeArtifact(
            seed: "router-plan", projectID: projectID, provider: .superpowers,
            name: "docs/superpowers/plans/current.md", revisedAt: 31)
        let brainstorm = Self.resumeArtifact(
            seed: "router-brainstorm", projectID: projectID, provider: .superpowers,
            name: ".superpowers/brainstorm/current.md", revisedAt: 32)
        let graph = Self.resumeArtifact(
            seed: "router-graph", projectID: projectID, provider: .graphify,
            name: "graphs/current.json", revisedAt: 33)
        let decision = Self.resumeKnowledge(
            seed: "router-decision", projectID: projectID, kind: .decision,
            summary: String(repeating: "é", count: 300), source: .artifact(plan.artifact.id),
            createdAt: 34)
        let todo = Self.resumeKnowledge(
            seed: "router-todo", projectID: projectID, kind: .todo,
            summary: "Ship the compact resume", source: .session(session.id), createdAt: 35)
        let question = Self.resumeKnowledge(
            seed: "router-question", projectID: projectID, kind: .question,
            summary: "What comes next?", source: .artifact(graph.artifact.id), createdAt: 36)
        populatedResume = ProjectResume(
            project: project,
            recentSession: SessionContextRecord(
                session: session, messageCount: 7, toolActivityCount: 3),
            lastPresence: DevicePresence(
                projectID: projectID, deviceID: DeviceID.derived(fromSeed: "router-device"),
                lastSeenAt: Date(timeIntervalSince1970: 30)),
            latestArtifactRevisionAt: Date(timeIntervalSince1970: 40),
            latestKnowledgeEntryAt: Date(timeIntervalSince1970: 36),
            currentPlan: plan, latestBrainstorm: brainstorm, relevantGraphs: [graph],
            recentDecisions: [decision], openTodos: [todo], openQuestions: [question],
            hasMoreDecisions: true, hasMoreTodos: false, hasMoreQuestions: true)
        knowledgeEntry = KnowledgeEntry(
            id: KnowledgeEntryID.derived(fromSeed: "router-knowledge"),
            projectID: projectID, kind: .decision,
            summaryText: "fixture-secret " + String(repeating: "é", count: 300),
            source: .session(session.id),
            sourceContentHash: ContentHash.digest(of: Data("knowledge source".utf8)),
            origin: .marked,
            supportingMessageIDs: [
                MessageID.derived(fromSeed: "second"), MessageID.derived(fromSeed: "first"),
            ], createdAt: Date(timeIntervalSince1970: 42))
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
            resume: BuildProjectResumeAction(
                workspace: self, resumes: self, availability: self),
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
                workspace: self, entries: self, availability: self),
            listKnowledge: ListProjectKnowledgeAction(
                workspace: self, knowledge: self, availability: self),
            readKnowledge: ReadProjectKnowledgeAction(
                workspace: self, knowledge: self, availability: self))
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
    func loadProjectResume(
        for project: ProjectContext, limits: ProjectResumeLimits
    ) async throws -> ProjectResume {
        operations.append("resume")
        return includesSession ? populatedResume : ProjectResume(project: project)
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

    func listCurrentKnowledge(
        forProject projectID: ProjectID, kind: KnowledgeEntryKind?,
        origin: KnowledgeEntryOrigin?, page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<KnowledgeEntry> {
        operations.append("knowledge-list")
        requestedKnowledgeKind = kind
        requestedKnowledgeOrigin = origin
        requestedKnowledgeLimit = page.limit
        if page.cursor != nil { throw ContextQueryFailure.invalidCursor }
        return ContextPage(
            records: [knowledgeEntry],
            nextCursor: ContextPageCursor(rawValue: "knowledge-next"))
    }

    func loadCurrentKnowledge(
        withIdentifier knowledgeEntryID: KnowledgeEntryID, forProject projectID: ProjectID
    ) async throws -> KnowledgeEntry? {
        operations.append("knowledge-detail")
        return knowledgeEntryID == knowledgeEntry.id ? knowledgeEntry : nil
    }

}
