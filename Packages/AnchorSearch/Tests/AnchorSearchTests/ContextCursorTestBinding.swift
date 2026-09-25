import AnchorApplication
import AnchorDomain
import Foundation

@testable import AnchorSearch

let contextCursorTestBinding = ContextCursorBinding(
    workspaceURL: URL(filePath: "/test/context-workspace"),
    generation: ContextReadGeneration(
        identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))

let siblingWorkspaceCursorBinding = ContextCursorBinding(
    workspaceURL: URL(filePath: "/sibling/context-workspace"),
    generation: contextCursorTestBinding.generation)

let expiredGenerationCursorBinding = ContextCursorBinding(
    workspaceURL: URL(filePath: "/test/context-workspace"),
    generation: ContextReadGeneration(
        identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!))

extension SQLiteContextSearch {
    func searchContext(
        forProject projectID: ProjectID, matching text: String, page: ContextPageRequest
    ) async throws -> ContextPage<ProjectContextSearchHit> {
        try await searchContext(
            forProject: projectID, matching: text, page: page,
            binding: contextCursorTestBinding)
    }

    func listSessions(
        forProject projectID: ProjectID, provider: AgentProvider?, page: ContextPageRequest
    ) async throws -> ContextPage<SessionContextRecord> {
        try await listSessions(
            forProject: projectID, provider: provider, page: page,
            binding: contextCursorTestBinding)
    }

    func loadConversationEntries(
        inSession sessionID: SessionID, forProject projectID: ProjectID,
        page: ContextPageRequest
    ) async throws -> ContextPage<ConversationEntry> {
        try await loadConversationEntries(
            inSession: sessionID, forProject: projectID, page: page,
            binding: contextCursorTestBinding)
    }

    func loadConversationEntries(
        inSession sessionID: SessionID, page: ContextPageRequest
    ) async throws -> ContextPage<ConversationEntry> {
        try await loadConversationEntries(
            inSession: sessionID, page: page,
            binding: contextCursorTestBinding)
    }
}
