import Foundation

public struct SearchProjectContextRequest: Sendable {
    public let text: String
    public let page: ContextPageRequest

    public init?(text: String, limit: Int? = nil, cursor: ContextPageCursor? = nil) {
        let queryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty,
            let page = ContextPageRequest(limit: limit, cursor: cursor, maximumLimit: 100)
        else { return nil }
        self.text = queryText
        self.page = page
    }
}

public struct SearchProjectContextAction: Action {
    private let availability: any ContextAvailabilityReading
    private let workspace: any AuthorizedProjectContextReading
    private let search: any ProjectContextSearching

    public init(
        workspace: any AuthorizedProjectContextReading, search: any ProjectContextSearching,
        availability: any ContextAvailabilityReading
    ) {
        self.availability = availability
        self.workspace = workspace
        self.search = search
    }

    public func perform(
        _ request: SearchProjectContextRequest
    ) async throws -> ContextPage<ProjectContextSearchHit> {
        try await queryContext(availability: availability) {
            let project = try await workspace.loadAuthorizedProjectContext()
            return try await search.searchContext(
                forProject: project.projectID, matching: request.text, page: request.page)
        }
    }
}
