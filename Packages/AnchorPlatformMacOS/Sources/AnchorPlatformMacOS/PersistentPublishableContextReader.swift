import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import Foundation

public struct PersistentPublishableContextReader: PublishableProjectContextReading {
    private let artifacts: SQLiteArtifactContextStore
    private let knowledge: SQLiteKnowledgeStore

    public init(database: SQLiteDatabase) {
        artifacts = SQLiteArtifactContextStore(existingDatabase: database)
        knowledge = SQLiteKnowledgeStore(existingDatabase: database)
    }

    public func loadPublishableProjectContext(
        forWorkspaceAt workspaceURL: URL
    ) async throws -> PublishableProjectContext? {
        guard let project = try await artifacts.loadProjectContext(forWorkspaceAt: workspaceURL)
        else { return nil }

        return PublishableProjectContext(
            project: PublishedProjectDescriptor(
                projectID: project.projectID,
                displayName: project.displayName,
                canonicalRepositoryRemote: project.canonicalRepositoryRemote),
            artifacts: try await artifacts.loadArtifacts(forProject: project.projectID),
            knowledgeEntries: try await knowledge.entries(
                forProject: project.projectID, includingSuperseded: true))
    }
}
