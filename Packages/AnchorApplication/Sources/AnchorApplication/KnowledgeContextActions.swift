import AnchorDomain

public struct ListProjectKnowledgeRequest: Sendable {
    public let kind: KnowledgeEntryKind?
    public let origin: KnowledgeEntryOrigin?
    public let page: ContextPageRequest

    public init?(
        kind: KnowledgeEntryKind? = nil, origin: KnowledgeEntryOrigin? = nil,
        limit: Int? = nil, cursor: ContextPageCursor? = nil
    ) {
        guard
            let page = ContextPageRequest(
                limit: limit, cursor: cursor, defaultLimit: 50, maximumLimit: 100)
        else { return nil }
        self.kind = kind
        self.origin = origin
        self.page = page
    }
}

public struct ReadProjectKnowledgeRequest: Sendable {
    public let knowledgeEntryID: KnowledgeEntryID

    public init(knowledgeEntryID: KnowledgeEntryID) {
        self.knowledgeEntryID = knowledgeEntryID
    }
}

public struct ListProjectKnowledgeAction: Action {
    private let workspace: any AuthorizedProjectContextReading
    private let knowledge: any KnowledgeContextReading
    private let availability: any ContextAvailabilityReading

    public init(
        workspace: any AuthorizedProjectContextReading,
        knowledge: any KnowledgeContextReading,
        availability: any ContextAvailabilityReading
    ) {
        self.workspace = workspace
        self.knowledge = knowledge
        self.availability = availability
    }

    public func perform(
        _ request: ListProjectKnowledgeRequest
    ) async throws -> ContextPage<KnowledgeContextSummary> {
        try await queryContext(availability: availability) { generation in
            let project = try await workspace.loadAuthorizedProjectContext()
            let page = try await knowledge.listCurrentKnowledge(
                forProject: project.projectID, kind: request.kind, origin: request.origin,
                page: request.page,
                binding: ContextCursorBinding(
                    workspaceURL: project.workspaceURL, generation: generation))
            return ContextPage(
                records: page.records.map {
                    KnowledgeContextSummary(
                        compacting: $0,
                        maximumSummaryByteCount: ProjectResumeLimits.compact.maximumSummaryByteCount
                    )
                },
                nextCursor: page.nextCursor)
        }
    }
}

public struct ReadProjectKnowledgeAction: Action {
    private let workspace: any AuthorizedProjectContextReading
    private let knowledge: any KnowledgeContextReading
    private let availability: any ContextAvailabilityReading

    public init(
        workspace: any AuthorizedProjectContextReading,
        knowledge: any KnowledgeContextReading,
        availability: any ContextAvailabilityReading
    ) {
        self.workspace = workspace
        self.knowledge = knowledge
        self.availability = availability
    }

    public func perform(_ request: ReadProjectKnowledgeRequest) async throws -> KnowledgeEntry {
        try await queryContext(availability: availability) { _ in
            let project = try await workspace.loadAuthorizedProjectContext()
            guard
                let entry = try await knowledge.loadCurrentKnowledge(
                    withIdentifier: request.knowledgeEntryID, forProject: project.projectID),
                entry.projectID == project.projectID
            else { throw ContextQueryFailure.entityNotFound }
            return entry
        }
    }
}
