import AnchorApplication
import AnchorDomain
import Foundation

enum ArtifactContextCursorFailure: Error, Sendable, Equatable { case invalid }
enum ArtifactContextStoreFailure: Error, Sendable, Equatable { case malformedArtifactRecord }

public struct SQLiteArtifactContextStore:
    ProjectContextReading, ArtifactContextReading, ArtifactContextIndexing
{
    private let database: SQLiteDatabase

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
        .flatMap(Self.projectContext)
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
        page: ContextPageRequest
    ) async throws -> ContextPage<ArtifactContextRecord> {
        let providerBinding = provider?.rawValue ?? ""
        let cursorPosition = try ArtifactContextCursor.decode(
            page.cursor,
            projectID: projectID,
            providerBinding: providerBinding)
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
                providerBinding: providerBinding)
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

    private static func record(
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

    private static func projectContext(from row: [String: SQLiteValue]) -> ProjectContext? {
        guard let workspacePath = row["workspace_path"]?.text,
            let projectID = row["project_id"]?.text.flatMap(ProjectID.init(rawValue:)),
            let displayName = row["display_name"]?.text
        else { return nil }

        let canonicalRemote: CanonicalRepositoryRemote?
        if let remoteValue = row["canonical_remote"]?.text {
            guard let parsedRemote = CanonicalRepositoryRemote(rawValue: remoteValue)
            else { return nil }
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

    private static func artifactContextRecord(
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

    private static func date(fromRevisedAt revisedAt: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(revisedAt) / 1_000_000)
    }
}

private enum ArtifactContextCursor {
    private static let version = 1

    static func encode(
        after record: ArtifactContextRecord?,
        projectID: ProjectID,
        providerBinding: String
    ) throws -> ContextPageCursor? {
        guard let record, let revision = record.latestRevision else { return nil }

        let payload = Payload(
            version: version,
            projectID: projectID.rawValue,
            providerBinding: providerBinding,
            revisedAt: SQLiteArtifactContextStore.revisedAt(for: revision.createdAt),
            artifactID: record.artifact.id.rawValue)
        let encodedPayload = try JSONEncoder().encode(payload)
        let token = encodedPayload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        guard let cursor = ContextPageCursor(rawValue: token) else {
            throw ArtifactContextCursorFailure.invalid
        }
        return cursor
    }

    fileprivate static func decode(
        _ cursor: ContextPageCursor?,
        projectID: ProjectID,
        providerBinding: String
    ) throws -> Position? {
        guard let cursor else { return nil }
        guard cursor.rawValue.allSatisfy(Self.isURLSafeBase64Character) else {
            throw ArtifactContextCursorFailure.invalid
        }

        var encodedPayload = cursor.rawValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encodedPayload.append(String(repeating: "=", count: (4 - encodedPayload.count % 4) % 4))

        guard let payloadBytes = Data(base64Encoded: encodedPayload),
            let payload = try? JSONDecoder().decode(Payload.self, from: payloadBytes),
            payload.version == version,
            payload.projectID == projectID.rawValue,
            payload.providerBinding == providerBinding,
            !payload.artifactID.isEmpty
        else { throw ArtifactContextCursorFailure.invalid }

        return Position(revisedAt: payload.revisedAt, artifactID: payload.artifactID)
    }

    private static func isURLSafeBase64Character(_ character: Character) -> Bool {
        character.isASCII
            && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }

    fileprivate struct Position {
        let revisedAt: Int64
        let artifactID: String
    }

    private struct Payload: Codable {
        let version: Int
        let projectID: String
        let providerBinding: String
        let revisedAt: Int64
        let artifactID: String
    }
}
