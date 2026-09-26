import AnchorApplication
import AnchorDomain
import Foundation

extension SQLiteArtifactContextStore {
    public func loadProjectResumeArtifacts(
        forProject projectID: ProjectID, maximumGraphCount: Int
    ) async throws -> (
        latestArtifactRevisionAt: Date?,
        currentPlan: ArtifactContextRecord?,
        latestBrainstorm: ArtifactContextRecord?,
        relevantGraphs: [ArtifactContextRecord]
    ) {
        let latestArtifactRevisionAt = try await loadLatestArtifactRevisionDate(
            forProject: projectID)
        let currentPlan = try await loadLatestResumeArtifact(
            forProject: projectID, provider: .superpowers,
            directoryPrefix: "docs/superpowers/plans/")
        let latestBrainstorm = try await loadLatestResumeArtifact(
            forProject: projectID, provider: .superpowers,
            directoryPrefix: ".superpowers/brainstorm/")
        let relevantGraphs = try await loadRelevantGraphs(
            forProject: projectID, maximumCount: maximumGraphCount)

        return (
            latestArtifactRevisionAt: latestArtifactRevisionAt,
            currentPlan: currentPlan,
            latestBrainstorm: latestBrainstorm,
            relevantGraphs: relevantGraphs
        )
    }

    private func loadLatestArtifactRevisionDate(
        forProject projectID: ProjectID
    ) async throws -> Date? {
        let rows = try await database.run(
            """
            SELECT revised_at
            FROM context_artifacts
            WHERE project_id = ?
            ORDER BY revised_at DESC, artifact_id ASC
            LIMIT 1;
            """,
            [.text(projectID.rawValue)])
        guard let row = rows.first else { return nil }
        guard let revisedAt = row["revised_at"]?.integer
        else { throw ArtifactContextStoreFailure.malformedArtifactRecord }
        return Self.date(fromRevisedAt: revisedAt)
    }

    private func loadLatestResumeArtifact(
        forProject projectID: ProjectID, provider: AgentProvider, directoryPrefix: String
    ) async throws -> ArtifactContextRecord? {
        try await database.run(
            """
            SELECT artifact_id, project_id, provider, name, revision_id, content_hash, revised_at
            FROM context_artifacts
            WHERE project_id = ? AND provider = ? AND name GLOB ?
            ORDER BY revised_at DESC, artifact_id ASC
            LIMIT 1;
            """,
            [
                .text(projectID.rawValue), .text(provider.rawValue),
                .text("\(directoryPrefix)*"),
            ]
        )
        .first
        .map(Self.artifactContextRecord)
    }

    private func loadRelevantGraphs(
        forProject projectID: ProjectID, maximumCount: Int
    ) async throws -> [ArtifactContextRecord] {
        let rows = try await database.run(
            """
            SELECT artifact_id, project_id, provider, name, revision_id, content_hash, revised_at
            FROM context_artifacts
            WHERE project_id = ? AND provider = ?
            ORDER BY revised_at DESC, artifact_id ASC
            LIMIT ?;
            """,
            [
                .text(projectID.rawValue), .text(AgentProvider.graphify.rawValue),
                .integer(Int64(max(0, maximumCount))),
            ])
        return try rows.map(Self.artifactContextRecord)
    }
}
