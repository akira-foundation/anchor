import AnchorDomain

extension SQLiteArtifactContextStore {
    public func loadArtifacts(forProject projectID: ProjectID) async throws -> [Artifact] {
        try await database.run(
            """
            SELECT artifact_id, project_id, provider, name, revision_id, content_hash, revised_at
            FROM context_artifacts
            WHERE project_id = ?
            ORDER BY artifact_id ASC;
            """,
            [.text(projectID.rawValue)]
        )
        .map { try Self.artifactContextRecord(from: $0).artifact }
    }
}
