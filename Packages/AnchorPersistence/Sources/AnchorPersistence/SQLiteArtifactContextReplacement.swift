import AnchorApplication
import AnchorDomain

extension SQLiteArtifactContextStore {
    public func replaceArtifactRevisions(
        _ revisions: [RecordedArtifactRevision], forProject projectID: ProjectID
    )
        async throws
    {
        guard revisions.allSatisfy({ $0.artifact.projectID == projectID }) else {
            throw ContextReplacementFailure.projectMismatch
        }
        try await database.withinTransaction { isolatedDatabase in
            for revision in revisions {
                let existing = try isolatedDatabase.run(
                    "SELECT project_id FROM context_artifacts WHERE artifact_id = ?;",
                    [.text(revision.artifact.id.rawValue)])
                guard existing.first?["project_id"]?.text.map({ $0 == projectID.rawValue }) ?? true
                else {
                    throw ContextReplacementFailure.projectMismatch
                }
            }
            try isolatedDatabase.run(
                "DELETE FROM context_artifacts WHERE project_id = ?;", [.text(projectID.rawValue)])
            for revision in revisions { try Self.record(revision, in: isolatedDatabase) }
        }
    }
}
