import AnchorApplication
import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

@Suite("SQLite artifact resume selection")
struct SQLiteArtifactResumeSelectionTests {
    @Test("resume artifacts are project scoped provider filtered bounded and deterministic")
    func resumeArtifactsFollowCanonicalSelectionRules() async throws {
        let projectID = ProjectID.derived(fromSeed: "resume-artifact-project")
        let otherProjectID = ProjectID.derived(fromSeed: "other-artifact-project")
        let database = try SQLiteDatabase(fileURL: nil)
        let store = try await SQLiteArtifactContextStore(database: database)
        let olderPlan = try record(
            "older-plan", projectID, .superpowers,
            "docs/superpowers/plans/25-old.md", revisedAt: 100)
        let currentPlan = try record(
            "current-plan", projectID, .superpowers,
            "docs/superpowers/plans/26-current.md", revisedAt: 500)
        let wrongProviderPlan = try record(
            "wrong-provider-plan", projectID, .codex,
            "docs/superpowers/plans/ignored.md", revisedAt: 900)
        let wrongDirectoryPlan = try record(
            "wrong-directory-plan", projectID, .superpowers,
            "docs/superpowers/plans-old/not-a-plan.md", revisedAt: 950)
        let brainstorm = try record(
            "brainstorm", projectID, .superpowers,
            ".superpowers/brainstorm/context-resume.md", revisedAt: 450)
        let foreignBrainstorm = try record(
            "foreign-brainstorm", otherProjectID, .superpowers,
            ".superpowers/brainstorm/foreign.md", revisedAt: 1_000)
        let omittedLatest = try record(
            "omitted-latest", projectID, .claude, "notes/latest.md", revisedAt: 1_100)
        let graphs = try (0..<4).map { offset in
            try record(
                "graph-\(offset)", projectID, .graphify, "graphs/graph-\(offset).json",
                revisedAt: 300)
        }
        let fakeGraph = try record(
            "fake-graph", projectID, .codex, "graphs/fake.json", revisedAt: 800)
        let foreignGraph = try record(
            "foreign-graph", otherProjectID, .graphify, "graphs/foreign.json", revisedAt: 850)
        try await store.indexArtifactRevisions(
            [
                olderPlan, currentPlan, wrongProviderPlan, wrongDirectoryPlan, brainstorm,
                foreignBrainstorm, omittedLatest, fakeGraph, foreignGraph,
            ] + graphs)
        try await database.run(
            "UPDATE context_artifacts SET content_hash = 'bad' WHERE artifact_id = ?;",
            [.text(omittedLatest.artifact.id.rawValue)])

        let selection = try await store.loadProjectResumeArtifacts(
            forProject: projectID, maximumGraphCount: 3)
        let expectedGraphIDs = graphs.map(\.artifact.id)
            .sorted { $0.rawValue < $1.rawValue }.prefix(3)

        #expect(selection.latestArtifactRevisionAt == date(1_100))
        #expect(selection.currentPlan?.artifact.id == currentPlan.artifact.id)
        #expect(selection.latestBrainstorm?.artifact.id == brainstorm.artifact.id)
        #expect(selection.relevantGraphs.map(\.artifact.id) == Array(expectedGraphIDs))
        #expect(selection.relevantGraphs.count == 3)
    }

    private func record(
        _ seed: String, _ projectID: ProjectID, _ provider: AgentProvider, _ name: String,
        revisedAt: TimeInterval
    ) throws -> RecordedArtifactRevision {
        let artifact = try #require(
            Artifact(
                id: ArtifactID.derived(fromSeed: seed), projectID: projectID,
                provider: provider, name: name))
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID.derived(fromSeed: "\(seed)-revision"),
                artifactID: artifact.id, parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data(seed.utf8)),
                deviceID: DeviceID.derived(fromSeed: "artifact-device"),
                createdAt: date(revisedAt), retention: artifact.retention))
        return RecordedArtifactRevision(artifact: artifact, revision: revision)
    }

    private func date(_ secondsSinceEpoch: TimeInterval) -> Date {
        Date(timeIntervalSince1970: secondsSinceEpoch)
    }
}
