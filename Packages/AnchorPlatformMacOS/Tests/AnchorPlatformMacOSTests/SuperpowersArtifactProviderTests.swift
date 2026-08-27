import AnchorDomain
import AnchorProvider
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Superpowers artifact provider")
struct SuperpowersArtifactProviderTests {
    private let projectID = ProjectID()

    @Test("every location the plugin writes to is discovered")
    func everyLocationThePluginWritesToIsDiscovered() async throws {
        let workspace = try WorkspaceFixture.make([
            "docs/superpowers/plans/00-indice.md": "plan",
            "docs/superpowers/specs/01-scaffold.md": "spec",
            ".superpowers/brainstorm/idea.md": "brainstorm",
            ".superpowers/sdd/design-review.md": "review",
        ])
        let provider = SuperpowersArtifactProvider(workspaceURL: workspace)

        let discovered = try await provider.discoverArtifacts(forProject: projectID)

        #expect(
            Set(discovered.map(\.artifact.name)) == [
                "docs/superpowers/plans/00-indice.md",
                "docs/superpowers/specs/01-scaffold.md",
                ".superpowers/brainstorm/idea.md",
                ".superpowers/sdd/design-review.md",
            ])
    }

    @Test("a capitalized Docs directory yields the same canonical name as a lowercase one")
    func aCapitalizedDocsDirectoryYieldsTheSameCanonicalName() async throws {
        let capitalized = try WorkspaceFixture.make(["Docs/superpowers/plans/00-indice.md": "plan"])
        let lowercased = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])

        let fromCapitalized = try await SuperpowersArtifactProvider(workspaceURL: capitalized)
            .discoverArtifacts(forProject: projectID)
        let fromLowercased = try await SuperpowersArtifactProvider(workspaceURL: lowercased)
            .discoverArtifacts(forProject: projectID)

        #expect(fromCapitalized.first?.artifact.name == "docs/superpowers/plans/00-indice.md")
        #expect(fromCapitalized.first?.artifact.name == fromLowercased.first?.artifact.name)
        #expect(fromCapitalized.first?.contentHash == fromLowercased.first?.contentHash)
    }

    @Test("a file outside the four locations is never discovered")
    func aFileOutsideTheFourLocationsIsNeverDiscovered() async throws {
        let workspace = try WorkspaceFixture.make([
            "docs/superpowers/plans/kept.md": "plan",
            "docs/architecture.md": "not superpowers",
            "README.md": "not superpowers",
            ".superpowers/notes/stray.md": "unknown location",
        ])
        let provider = SuperpowersArtifactProvider(workspaceURL: workspace)

        let discovered = try await provider.discoverArtifacts(forProject: projectID)

        #expect(discovered.map(\.artifact.name) == ["docs/superpowers/plans/kept.md"])
    }

    @Test("a workspace with none of the locations returns nothing rather than failing")
    func aWorkspaceWithNoneOfTheLocationsReturnsNothing() async throws {
        let workspace = try WorkspaceFixture.make(["README.md": "nothing to see"])
        let provider = SuperpowersArtifactProvider(workspaceURL: workspace)

        let discovered = try await provider.discoverArtifacts(forProject: projectID)

        #expect(discovered.isEmpty)
    }

    @Test("unchanged content discovered twice keeps the same digest")
    func unchangedContentDiscoveredTwiceKeepsTheSameDigest() async throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00-indice.md": "plan"])
        let provider = SuperpowersArtifactProvider(workspaceURL: workspace)

        let first = try await provider.discoverArtifacts(forProject: projectID)
        let second = try await provider.discoverArtifacts(forProject: projectID)

        #expect(first.first?.contentHash == second.first?.contentHash)
    }

    @Test("every discovered artifact belongs to the superpowers provider and the given project")
    func everyDiscoveredArtifactBelongsToTheSuperpowersProviderAndTheGivenProject() async throws {
        let workspace = try WorkspaceFixture.make([".superpowers/sdd/design-review.md": "review"])
        let provider = SuperpowersArtifactProvider(workspaceURL: workspace)

        let discovered = try #require(
            try await provider.discoverArtifacts(forProject: projectID).first
        )

        #expect(discovered.artifact.provider == .superpowers)
        #expect(discovered.artifact.projectID == projectID)
    }
}

enum WorkspaceFixture {
    static func make(_ files: [String: String]) throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appending(path: "anchor-workspace-fixtures/\(UUID().uuidString)")

        for (relativePath, contents) in files {
            let fileURL = workspace.appending(path: relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: fileURL)
        }

        return workspace
    }
}
