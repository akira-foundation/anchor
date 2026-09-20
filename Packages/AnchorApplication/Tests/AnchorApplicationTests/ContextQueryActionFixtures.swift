import AnchorDomain
import Foundation

@testable import AnchorApplication

struct ContextQueryFixture: AuthorizedProjectContextReading, ArtifactContextReading,
    SessionContextReading,
    ArtifactRevisionContentReading, ProjectConversationReading, ContextAvailabilityReading
{
    let generation = ContextReadGeneration(identifier: UUID())
    let project: ProjectContext
    let artifact: Artifact
    let revision: ArtifactRevision
    let unrelatedRevision: ArtifactRevision
    let session: AgentSession
    let hasSession: Bool

    init(hasSession: Bool = true) throws {
        let projectID = ProjectID.derived(fromSeed: "query-project")
        project = ProjectContext(
            projectID: projectID, displayName: "Query", canonicalRepositoryRemote: nil,
            workspaceURL: URL(filePath: "/query"))
        artifact = Artifact(
            id: ArtifactID(), projectID: projectID, provider: .codex, name: "plan.md")!
        revision = ArtifactRevision(
            id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
            contentHash: ContentHash.digest(of: Data("ab😀cd".utf8)), deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: 10))!
        unrelatedRevision = ArtifactRevision(
            id: RevisionID(), artifactID: ArtifactID(), parentRevisionID: nil,
            contentHash: revision.contentHash, deviceID: DeviceID(), createdAt: revision.createdAt)!
        session = AgentSession(
            id: SessionID(), projectID: projectID, provider: .codex,
            startedAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 20))
        self.hasSession = hasSession
    }

    var artifactAction: ReadProjectArtifactAction {
        ReadProjectArtifactAction(
            workspace: self, artifacts: self, content: self, availability: self)
    }

    func loadAuthorizedProjectContext() async throws -> ProjectContext { project }
    func loadAvailableGeneration() async throws -> ContextReadGeneration { generation }
    func loadArtifact(withIdentifier artifactID: ArtifactID) async throws -> ArtifactContextRecord?
    {
        artifactID == artifact.id
            ? ArtifactContextRecord(artifact: artifact, latestRevision: revision) : nil
    }
    func listArtifacts(
        forProject projectID: ProjectID, provider: AgentProvider?, page: ContextPageRequest
    )
        async throws -> ContextPage<ArtifactContextRecord>
    {
        ContextPage(
            records: Array(
                repeating: ArtifactContextRecord(artifact: artifact, latestRevision: revision)!,
                count: page.limit), nextCursor: nil)
    }
    func loadRevision(withIdentifier revisionID: RevisionID) async throws -> ArtifactRevision? {
        revision
    }
    func readContent(forRevision revisionID: RevisionID) async throws -> Data? {
        Data("ab😀cd".utf8)
    }
    func loadSession(withIdentifier sessionID: SessionID) async throws -> SessionContextRecord? {
        sessionID == session.id
            ? SessionContextRecord(session: session, messageCount: 7, toolActivityCount: 3) : nil
    }
    func listSessions(
        forProject projectID: ProjectID, provider: AgentProvider?, page: ContextPageRequest
    )
        async throws -> ContextPage<SessionContextRecord>
    {
        ContextPage(
            records: hasSession
                ? Array(repeating: SessionContextRecord(session: session), count: page.limit) : [],
            nextCursor: nil)
    }
    func loadConversationEntries(
        inSession sessionID: SessionID, forProject projectID: ProjectID,
        page: ContextPageRequest
    ) async throws -> ContextPage<ConversationEntry> {
        guard sessionID == session.id, projectID == session.projectID else {
            throw ContextQueryFailure.entityNotFound
        }
        return try await loadConversationEntries(inSession: sessionID, page: page)
    }
    func loadConversationEntries(
        inSession sessionID: SessionID, page: ContextPageRequest
    )
        async throws -> ContextPage<ConversationEntry>
    {
        ContextPage(
            records: (0..<page.limit).map { offset in
                .message(
                    ConversationMessage(
                        id: MessageID.derived(fromSeed: "\(offset)"), sessionID: sessionID,
                        role: .user, content: "message", timestamp: Date(timeIntervalSince1970: 20))
                )
            }, nextCursor: nil)
    }
}

actor QuerySearchSpy: ProjectContextSearching {
    enum Failure: Error { case cursor, storage, unavailable }
    let failure: Failure?
    var requestedLimit: Int?
    var requestedProject: ProjectID?
    init(failure: Failure? = nil) { self.failure = failure }
    func searchContext(
        forProject projectID: ProjectID, matching text: String, page: ContextPageRequest
    )
        async throws -> ContextPage<ProjectContextSearchHit>
    {
        requestedLimit = page.limit
        requestedProject = projectID
        switch failure {
        case .cursor: throw ContextCursorFailure.invalid
        case .storage: throw Failure.storage
        case .unavailable: throw ContextQueryFailure.contextUnavailable
        case nil: return ContextPage(records: [], nextCursor: nil)
        }
    }
}

actor QueryContentSpy: ArtifactRevisionContentReading {
    let revision: ArtifactRevision
    let bytes: Data
    var revisionReads = 0
    var contentReads = 0
    init(revision: ArtifactRevision, bytes: Data = Data("content".utf8)) {
        self.revision = revision
        self.bytes = bytes
    }
    func loadRevision(withIdentifier revisionID: RevisionID) async throws -> ArtifactRevision? {
        revisionReads += 1
        return revision
    }
    func readContent(forRevision revisionID: RevisionID) async throws -> Data? {
        contentReads += 1
        return bytes
    }
}
