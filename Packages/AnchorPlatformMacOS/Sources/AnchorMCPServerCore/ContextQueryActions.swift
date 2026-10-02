import AnchorApplication
import AnchorDomain

public struct ContextQueryActions: Sendable {
    public let currentProject: ResolveCurrentProjectAction
    public let resume: BuildProjectResumeAction
    public let search: SearchProjectContextAction
    public let listArtifacts: ListProjectArtifactsAction
    public let readArtifact: ReadProjectArtifactAction
    public let listSessions: ListProjectSessionsAction
    public let readSession: ReadProjectSessionAction
    public let readMessages: ReadSessionMessagesAction
    public let listKnowledge: ListProjectKnowledgeAction
    public let readKnowledge: ReadProjectKnowledgeAction

    public init(
        currentProject: ResolveCurrentProjectAction, resume: BuildProjectResumeAction,
        search: SearchProjectContextAction, listArtifacts: ListProjectArtifactsAction,
        readArtifact: ReadProjectArtifactAction, listSessions: ListProjectSessionsAction,
        readSession: ReadProjectSessionAction, readMessages: ReadSessionMessagesAction,
        listKnowledge: ListProjectKnowledgeAction, readKnowledge: ReadProjectKnowledgeAction
    ) {
        self.currentProject = currentProject
        self.resume = resume
        self.search = search
        self.listArtifacts = listArtifacts
        self.readArtifact = readArtifact
        self.listSessions = listSessions
        self.readSession = readSession
        self.readMessages = readMessages
        self.listKnowledge = listKnowledge
        self.readKnowledge = readKnowledge
    }

    public init(
        currentProject: ResolveCurrentProjectAction, resume: BuildProjectResumeAction,
        search: SearchProjectContextAction, listArtifacts: ListProjectArtifactsAction,
        readArtifact: ReadProjectArtifactAction, listSessions: ListProjectSessionsAction,
        readSession: ReadProjectSessionAction, readMessages: ReadSessionMessagesAction
    ) {
        let unavailable = UnavailableKnowledgeContext()
        self.init(
            currentProject: currentProject, resume: resume, search: search,
            listArtifacts: listArtifacts, readArtifact: readArtifact,
            listSessions: listSessions, readSession: readSession, readMessages: readMessages,
            listKnowledge: ListProjectKnowledgeAction(
                workspace: unavailable, knowledge: unavailable, availability: unavailable),
            readKnowledge: ReadProjectKnowledgeAction(
                workspace: unavailable, knowledge: unavailable, availability: unavailable))
    }
}

private struct UnavailableKnowledgeContext: AuthorizedProjectContextReading,
    ContextAvailabilityReading, KnowledgeContextReading
{
    func loadAvailableGeneration() async throws -> ContextReadGeneration {
        throw ContextQueryFailure.contextUnavailable
    }

    func loadAuthorizedProjectContext() async throws -> ProjectContext {
        throw ContextQueryFailure.contextUnavailable
    }

    func listCurrentKnowledge(
        forProject projectID: ProjectID, kind: KnowledgeEntryKind?,
        origin: KnowledgeEntryOrigin?, page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<KnowledgeEntry> {
        throw ContextQueryFailure.contextUnavailable
    }

    func loadCurrentKnowledge(
        withIdentifier knowledgeEntryID: KnowledgeEntryID, forProject projectID: ProjectID
    ) async throws -> KnowledgeEntry? {
        throw ContextQueryFailure.contextUnavailable
    }
}
