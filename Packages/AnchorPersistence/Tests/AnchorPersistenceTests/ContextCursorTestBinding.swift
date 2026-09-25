import AnchorApplication
import AnchorDomain
import Foundation

@testable import AnchorPersistence

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

extension SQLiteArtifactContextStore {
    func listArtifacts(
        forProject projectID: ProjectID, provider: AgentProvider?, page: ContextPageRequest
    ) async throws -> ContextPage<ArtifactContextRecord> {
        try await listArtifacts(
            forProject: projectID, provider: provider, page: page,
            binding: contextCursorTestBinding)
    }
}
