import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Context query contracts")
struct ContextQueryContractTests {
    @Test("page requests reject zero and values above their tool maximum")
    func pageRequestsRejectOutOfRangeLimits() {
        #expect(ContextPageRequest(limit: 0, maximumLimit: 100) == nil)
        #expect(ContextPageRequest(limit: 101, maximumLimit: 100) == nil)
        #expect(ContextPageRequest(limit: nil, defaultLimit: 20, maximumLimit: 100)?.limit == 20)
    }

    @Test("page cursors reject empty and padded text")
    func pageCursorsRejectEmptyAndPaddedText() {
        #expect(ContextPageCursor(rawValue: "") == nil)
        #expect(ContextPageCursor(rawValue: " next-page") == nil)
        #expect(ContextPageCursor(rawValue: "next-page ") == nil)
        #expect(ContextPageCursor(rawValue: "next-page")?.rawValue == "next-page")
    }

    @Test("artifact context rejects a latest revision from another artifact")
    func artifactContextRejectsRevisionFromAnotherArtifact() throws {
        let artifact = try #require(
            Artifact(
                id: ArtifactID(), projectID: ProjectID(), provider: .codex,
                name: "session.json"
            ))
        let unrelatedRevision = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: ArtifactID(), parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("context".utf8)),
                deviceID: DeviceID(), createdAt: Date(timeIntervalSince1970: 0)
            ))

        #expect(ArtifactContextRecord(artifact: artifact, latestRevision: unrelatedRevision) == nil)
    }

    @Test("artifact context accepts a latest revision from the same artifact")
    func artifactContextAcceptsMatchingRevision() throws {
        let artifact = try #require(
            Artifact(
                id: ArtifactID(), projectID: ProjectID(), provider: .codex,
                name: "session.json"
            ))
        let revision = try #require(
            ArtifactRevision(
                id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
                contentHash: ContentHash.digest(of: Data("context".utf8)),
                deviceID: DeviceID(), createdAt: Date(timeIntervalSince1970: 0)
            ))

        #expect(ArtifactContextRecord(artifact: artifact, latestRevision: revision) != nil)
    }

    @Test("project context preserves the authorized workspace spelling")
    func projectContextPreservesAuthorizedWorkspace() throws {
        let workspaceURL = URL(filePath: "/Developer/anchor")
        let context = ProjectContext(
            projectID: ProjectID.derived(fromSeed: "anchor"),
            displayName: "anchor",
            canonicalRepositoryRemote: CanonicalRepositoryRemote(
                gitRemote: "git@github.com:akira-foundation/anchor.git"),
            workspaceURL: workspaceURL
        )

        #expect(context.workspaceURL == workspaceURL)
    }
}
