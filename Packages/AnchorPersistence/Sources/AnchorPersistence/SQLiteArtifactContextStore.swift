import AnchorApplication
import AnchorDomain
import Foundation

enum ArtifactContextStoreFailure: Error, Sendable, Equatable {
    case malformedArtifactRecord
    case malformedProjectRecord
}

public struct SQLiteArtifactContextStore:
    ProjectContextReading, ArtifactContextReading, ArtifactContextIndexing, ArtifactContextReplacing
{
    let database: SQLiteDatabase

    public init(existingDatabase: SQLiteDatabase) {
        database = existingDatabase
    }

    public init(database: SQLiteDatabase) async throws {
        self.database = database
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS context_projects (
                workspace_path TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                canonical_remote TEXT
            );
            CREATE TABLE IF NOT EXISTS context_artifacts (
                artifact_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                provider TEXT NOT NULL,
                name TEXT NOT NULL,
                revision_id TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                revised_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS context_artifacts_by_project
                ON context_artifacts(project_id, revised_at DESC, artifact_id);
            """
        )
    }

    public func recordProjectContext(_ context: ProjectContext) async throws {
        try await database.run(
            """
            INSERT INTO context_projects (
                workspace_path, project_id, display_name, canonical_remote
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(workspace_path) DO UPDATE SET
                project_id = excluded.project_id,
                display_name = excluded.display_name,
                canonical_remote = excluded.canonical_remote;
            """,
            [
                .text(context.workspaceURL.path(percentEncoded: false)),
                .text(context.projectID.rawValue),
                .text(context.displayName),
                context.canonicalRepositoryRemote.map { .text($0.rawValue) } ?? .null,
            ])
    }

    public func loadProjectContext(
        forWorkspaceAt workspaceURL: URL
    ) async throws -> ProjectContext? {
        try await database.run(
            """
            SELECT workspace_path, project_id, display_name, canonical_remote
            FROM context_projects WHERE workspace_path = ? LIMIT 1;
            """,
            [.text(workspaceURL.path(percentEncoded: false))]
        )
        .first
        .map(Self.projectContext)
    }

    public func indexArtifactRevisions(_ revisions: [RecordedArtifactRevision]) async throws {
        try await database.withinTransaction { isolatedDatabase in
            for recordedRevision in revisions {
                try Self.record(recordedRevision, in: isolatedDatabase)
            }
        }
    }

    public func listArtifacts(
        forProject projectID: ProjectID,
        provider: AgentProvider?,
        page: ContextPageRequest,
        binding: ContextCursorBinding
    ) async throws -> ContextPage<ArtifactContextRecord> {
        let providerBinding = provider?.rawValue ?? ""
        let cursorPosition = try ArtifactContextCursor.decode(
            page.cursor,
            projectID: projectID,
            providerBinding: providerBinding,
            binding: binding)
        var statement = """
            SELECT artifact_id, project_id, provider, name, revision_id, content_hash, revised_at
            FROM context_artifacts
            WHERE project_id = ?
            """
        var parameters: [SQLiteValue] = [.text(projectID.rawValue)]

        if let provider {
            statement += " AND provider = ?"
            parameters.append(.text(provider.rawValue))
        }
        if let cursorPosition {
            statement += " AND (revised_at < ? OR (revised_at = ? AND artifact_id > ?))"
            parameters += [
                .integer(cursorPosition.revisedAt),
                .integer(cursorPosition.revisedAt),
                .text(cursorPosition.artifactID),
            ]
        }
        statement += " ORDER BY revised_at DESC, artifact_id ASC LIMIT ?;"
        parameters.append(.integer(Int64(page.limit) + 1))

        let artifactRows = try await database.run(statement, parameters)
        let records = try artifactRows.map(Self.artifactContextRecord)
        let pageRecords = Array(records.prefix(page.limit))
        let nextCursor =
            try artifactRows.count > page.limit
            ? ArtifactContextCursor.encode(
                after: pageRecords.last,
                projectID: projectID,
                providerBinding: providerBinding,
                binding: binding)
            : nil

        return ContextPage(records: pageRecords, nextCursor: nextCursor)
    }

    public func loadArtifact(
        withIdentifier artifactID: ArtifactID
    ) async throws -> ArtifactContextRecord? {
        try await database.run(
            """
            SELECT artifact_id, project_id, provider, name, revision_id, content_hash, revised_at
            FROM context_artifacts WHERE artifact_id = ? LIMIT 1;
            """,
            [.text(artifactID.rawValue)]
        )
        .first
        .map(Self.artifactContextRecord)
    }

    static func record(
        _ recordedRevision: RecordedArtifactRevision,
        in database: isolated SQLiteDatabase
    ) throws {
        try database.run(
            """
            INSERT INTO context_artifacts (
                artifact_id, project_id, provider, name, revision_id, content_hash, revised_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(artifact_id) DO UPDATE SET
                project_id = excluded.project_id,
                provider = excluded.provider,
                name = excluded.name,
                revision_id = excluded.revision_id,
                content_hash = excluded.content_hash,
                revised_at = excluded.revised_at
            WHERE excluded.revised_at >= context_artifacts.revised_at;
            """,
            [
                .text(recordedRevision.artifact.id.rawValue),
                .text(recordedRevision.artifact.projectID.rawValue),
                .text(recordedRevision.artifact.provider.rawValue),
                .text(recordedRevision.artifact.name),
                .text(recordedRevision.revision.id.rawValue),
                .text(recordedRevision.revision.contentHash.rawValue),
                .integer(Self.revisedAt(for: recordedRevision.revision.createdAt)),
            ])
    }

    private static func projectContext(from row: [String: SQLiteValue]) throws -> ProjectContext {
        guard let workspacePath = row["workspace_path"]?.text,
            let projectID = row["project_id"]?.text.flatMap(ProjectID.init(rawValue:)),
            let displayName = row["display_name"]?.text
        else { throw ArtifactContextStoreFailure.malformedProjectRecord }

        let canonicalRemote: CanonicalRepositoryRemote?
        if let remoteValue = row["canonical_remote"]?.text {
            guard let parsedRemote = CanonicalRepositoryRemote(rawValue: remoteValue)
            else { throw ArtifactContextStoreFailure.malformedProjectRecord }
            canonicalRemote = parsedRemote
        } else {
            canonicalRemote = nil
        }

        return ProjectContext(
            projectID: projectID,
            displayName: displayName,
            canonicalRepositoryRemote: canonicalRemote,
            workspaceURL: URL(filePath: workspacePath))
    }

    static func artifactContextRecord(
        from row: [String: SQLiteValue]
    ) throws -> ArtifactContextRecord {
        guard let artifactID = row["artifact_id"]?.text.flatMap(ArtifactID.init(rawValue:)),
            let projectID = row["project_id"]?.text.flatMap(ProjectID.init(rawValue:)),
            let provider = row["provider"]?.text.flatMap(AgentProvider.init(rawValue:)),
            let name = row["name"]?.text,
            let revisionID = row["revision_id"]?.text.flatMap(RevisionID.init(rawValue:)),
            let contentHash = row["content_hash"]?.text.flatMap(ContentHash.init(rawValue:)),
            let revisedAt = row["revised_at"]?.integer,
            let artifact = Artifact(
                id: artifactID, projectID: projectID, provider: provider, name: name),
            let revision = ArtifactRevision(
                id: revisionID,
                artifactID: artifactID,
                parentRevisionID: nil,
                contentHash: contentHash,
                deviceID: DeviceID.derived(fromSeed: revisionID.rawValue),
                createdAt: Self.date(fromRevisedAt: revisedAt),
                retention: artifact.retention)
        else { throw ArtifactContextStoreFailure.malformedArtifactRecord }

        guard let record = ArtifactContextRecord(artifact: artifact, latestRevision: revision)
        else { throw ArtifactContextStoreFailure.malformedArtifactRecord }

        return record
    }

    static func revisedAt(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    }

    static func date(fromRevisedAt revisedAt: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(revisedAt) / 1_000_000)
    }
}
