import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@testable import AnchorPersistence

@Suite("SQLite artifact context store")
struct SQLiteArtifactContextStoreTests {
    @Test("indexing revisions records artifact identity and current revision")
    func indexingRevisionsRecordsCurrentArtifactMetadata() async throws {
        let fileURL = makeFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let artifact = try makeArtifact(
            projectID: ProjectID(), provider: .claude, name: "session.json")
        let revision = try makeRevision(
            for: artifact,
            contents: "recorded session",
            createdAt: Date(timeIntervalSince1970: 1_701_234_567.125)
        )
        let database = try SQLiteDatabase(fileURL: fileURL)
        let store = try await SQLiteArtifactContextStore(database: database)

        try await store.indexArtifactRevisions([
            RecordedArtifactRevision(artifact: artifact, revision: revision)
        ])

        let reopenedDatabase = try SQLiteDatabase(fileURL: fileURL)
        let reopenedStore = try await SQLiteArtifactContextStore(database: reopenedDatabase)
        let recorded = try #require(
            try await reopenedStore.loadArtifact(withIdentifier: artifact.id))
        let revisedAtRows = try await reopenedDatabase.run(
            "SELECT revised_at FROM context_artifacts WHERE artifact_id = ?;",
            [.text(artifact.id.rawValue)]
        )

        #expect(recorded.artifact == artifact)
        #expect(recorded.latestRevision?.id == revision.id)
        #expect(recorded.latestRevision?.contentHash == revision.contentHash)
        #expect(recorded.latestRevision?.createdAt == revision.createdAt)
        #expect(revisedAtRows.first?["revised_at"] == .integer(1_701_234_567_125_000))
    }

    @Test("an older revision cannot replace newer current metadata")
    func olderRevisionCannotReplaceNewerCurrentMetadata() async throws {
        let artifact = try makeArtifact(projectID: ProjectID(), provider: .codex, name: "plan.md")
        let newer = try makeRevision(
            for: artifact, contents: "new", createdAt: Date(timeIntervalSince1970: 900))
        let older = try makeRevision(
            for: artifact, contents: "old", createdAt: Date(timeIntervalSince1970: 100))
        let store = try await SQLiteArtifactContextStore(database: try SQLiteDatabase(fileURL: nil))

        try await store.indexArtifactRevisions([
            RecordedArtifactRevision(artifact: artifact, revision: newer),
            RecordedArtifactRevision(artifact: artifact, revision: older),
        ])

        let recorded = try #require(try await store.loadArtifact(withIdentifier: artifact.id))

        #expect(recorded.latestRevision?.id == newer.id)
        #expect(recorded.latestRevision?.contentHash == newer.contentHash)
        #expect(recorded.latestRevision?.createdAt == newer.createdAt)
    }

    @Test("artifact pages stay inside their project and provider filter")
    func artifactPagesRespectProjectAndProvider() async throws {
        let firstProjectID = ProjectID()
        let secondProjectID = ProjectID()
        let firstClaudeArtifact = try makeArtifact(
            projectID: firstProjectID, provider: .claude, name: "first-session.json")
        let secondClaudeArtifact = try makeArtifact(
            projectID: firstProjectID, provider: .claude, name: "second-session.json")
        let codexArtifact = try makeArtifact(
            projectID: firstProjectID, provider: .codex, name: "plan.md")
        let otherProjectArtifact = try makeArtifact(
            projectID: secondProjectID, provider: .claude, name: "other-session.json")
        let store = try await SQLiteArtifactContextStore(database: try SQLiteDatabase(fileURL: nil))

        try await store.indexArtifactRevisions([
            RecordedArtifactRevision(
                artifact: firstClaudeArtifact,
                revision: try makeRevision(
                    for: firstClaudeArtifact,
                    contents: "first",
                    createdAt: Date(timeIntervalSince1970: 300)
                )),
            RecordedArtifactRevision(
                artifact: secondClaudeArtifact,
                revision: try makeRevision(
                    for: secondClaudeArtifact,
                    contents: "second",
                    createdAt: Date(timeIntervalSince1970: 200)
                )),
            RecordedArtifactRevision(
                artifact: codexArtifact,
                revision: try makeRevision(
                    for: codexArtifact,
                    contents: "plan",
                    createdAt: Date(timeIntervalSince1970: 100)
                )),
            RecordedArtifactRevision(
                artifact: otherProjectArtifact,
                revision: try makeRevision(
                    for: otherProjectArtifact,
                    contents: "other",
                    createdAt: Date(timeIntervalSince1970: 400)
                )),
        ])

        let firstPage = try await store.listArtifacts(
            forProject: firstProjectID, provider: .claude, page: makePage(limit: 1))
        guard let firstCursor = firstPage.nextCursor else {
            Issue.record("expected a continuation cursor")

            return
        }
        let secondPage = try await store.listArtifacts(
            forProject: firstProjectID,
            provider: .claude,
            page: makePage(limit: 1, cursor: firstCursor)
        )

        #expect(firstPage.records.map(\.artifact.id) == [firstClaudeArtifact.id])
        #expect(secondPage.records.map(\.artifact.id) == [secondClaudeArtifact.id])
        #expect(secondPage.nextCursor == nil)
        await #expect(throws: ContextCursorFailure.self) {
            try await store.listArtifacts(
                forProject: secondProjectID,
                provider: .claude,
                page: makePage(limit: 1, cursor: firstCursor)
            )
        }
    }

    @Test("recording a project replaces only the same workspace row")
    func recordingProjectContextIsWorkspaceScoped() async throws {
        let firstWorkspaceURL = URL(filePath: "/Developer/anchor")
        let secondWorkspaceURL = URL(filePath: "/Developer/other")
        let firstProjectID = ProjectID()
        let secondProjectID = ProjectID()
        let first = ProjectContext(
            projectID: firstProjectID,
            displayName: "Anchor",
            canonicalRepositoryRemote: CanonicalRepositoryRemote(
                gitRemote: "github.com/akira-foundation/anchor"),
            workspaceURL: firstWorkspaceURL
        )
        let second = ProjectContext(
            projectID: secondProjectID,
            displayName: "Other",
            canonicalRepositoryRemote: nil,
            workspaceURL: secondWorkspaceURL
        )
        let replacement = ProjectContext(
            projectID: firstProjectID,
            displayName: "Anchor renamed",
            canonicalRepositoryRemote: nil,
            workspaceURL: firstWorkspaceURL
        )
        let store = try await SQLiteArtifactContextStore(database: try SQLiteDatabase(fileURL: nil))

        try await store.recordProjectContext(first)
        try await store.recordProjectContext(second)
        try await store.recordProjectContext(replacement)

        #expect(
            try await store.loadProjectContext(forWorkspaceAt: firstWorkspaceURL) == replacement)
        #expect(
            try await store.loadProjectContext(forWorkspaceAt: secondWorkspaceURL) == second)
    }

    @Test("malformed artifact rows refuse listing and loading")
    func malformedArtifactRowsRefuseListingAndLoading() async throws {
        let projectID = ProjectID()
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteArtifactContextStore(database: database)
        let validArtifact = try makeArtifact(
            projectID: projectID, provider: .claude, name: "valid-session.json")
        let validRevision = try makeRevision(
            for: validArtifact, contents: "valid", createdAt: Date(timeIntervalSince1970: 100))
        let malformedArtifactID = ArtifactID()
        let laterMalformedArtifactID = ArtifactID()

        try await store.indexArtifactRevisions([
            RecordedArtifactRevision(artifact: validArtifact, revision: validRevision)
        ])
        for artifactID in [malformedArtifactID, laterMalformedArtifactID] {
            try await database.run(
                """
                INSERT INTO context_artifacts (
                    artifact_id, project_id, provider, name, revision_id, content_hash, revised_at
                ) VALUES (?, ?, 'unknown-provider', 'malformed.json', ?, ?, 300000000);
                """,
                [
                    .text(artifactID.rawValue),
                    .text(projectID.rawValue),
                    .text(RevisionID().rawValue),
                    .text(ContentHash.digest(of: Data("malformed".utf8)).rawValue),
                ])
        }

        await #expect(throws: ArtifactContextStoreFailure.malformedArtifactRecord) {
            try await store.listArtifacts(
                forProject: projectID, provider: nil, page: self.makePage(limit: 1))
        }
        await #expect(throws: ArtifactContextStoreFailure.malformedArtifactRecord) {
            try await store.loadArtifact(withIdentifier: malformedArtifactID)
        }
    }

    private func makeArtifact(
        projectID: ProjectID,
        provider: AgentProvider,
        name: String
    ) throws -> Artifact {
        try #require(
            Artifact(id: ArtifactID(), projectID: projectID, provider: provider, name: name))
    }

    private func makeRevision(
        for artifact: Artifact,
        contents: String,
        createdAt: Date
    ) throws -> ArtifactRevision {
        try #require(
            ArtifactRevision(
                id: RevisionID(),
                artifactID: artifact.id,
                parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data(contents.utf8)),
                deviceID: DeviceID(),
                createdAt: createdAt,
                retention: artifact.retention
            ))
    }

    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-artifact-context-\(UUID().uuidString)/index.sqlite")
    }

    private func makePage(limit: Int, cursor: ContextPageCursor? = nil) -> ContextPageRequest {
        ContextPageRequest(limit: limit, cursor: cursor, maximumLimit: 100)!
    }
}
