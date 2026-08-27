import AnchorDomain
import AnchorProvider
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Graphify artifact provider")
struct GraphifyArtifactProviderTests {
    private let projectID = ProjectID()

    private func discover(_ files: [String: String]) async throws -> [DiscoveredArtifact] {
        let provider = GraphifyArtifactProvider(workspaceURL: try WorkspaceFixture.make(files))

        return try await provider.discoverArtifacts(forProject: projectID)
    }

    @Test("only the graph and the report are discovered")
    func onlyTheGraphAndTheReportAreDiscovered() async throws {
        let discovered = try await discover([
            "graphify-out/graph.json": "{\"nodes\":[]}",
            "graphify-out/GRAPH_REPORT.md": "# Graph Report",
            "graphify-out/graph.html": "<html></html>",
            "graphify-out/manifest.json": "{}",
            "graphify-out/cost.json": "{}",
            "graphify-out/cache/ast/entry.json": "{}",
        ])

        #expect(
            Set(discovered.map(\.artifact.name)) == [
                "graphify-out/graph.json",
                "graphify-out/GRAPH_REPORT.md",
            ])
    }

    @Test("the derived visualization is never carried")
    func theDerivedVisualizationIsNeverCarried() async throws {
        let discovered = try await discover(["graphify-out/graph.html": "<html></html>"])

        #expect(discovered.isEmpty)
    }

    @Test("a graph is kept only at its latest revision, because the repository holds its history")
    func aGraphIsKeptOnlyAtItsLatestRevision() async throws {
        let discovered = try await discover([
            "graphify-out/graph.json": "{}",
            "graphify-out/GRAPH_REPORT.md": "# Graph Report",
        ])

        #expect(discovered.allSatisfy { $0.artifact.retention == .latestRevisionOnly })
    }

    @Test("a workspace that was never graphed returns nothing rather than failing")
    func aWorkspaceThatWasNeverGraphedReturnsNothing() async throws {
        #expect(try await discover(["README.md": "no graph here"]).isEmpty)
    }

    @Test("the same graph discovered twice keeps the same digest")
    func theSameGraphDiscoveredTwiceKeepsTheSameDigest() async throws {
        let files = ["graphify-out/graph.json": "{\"nodes\":[1]}"]
        let workspace = try WorkspaceFixture.make(files)
        let provider = GraphifyArtifactProvider(workspaceURL: workspace)

        let first = try await provider.discoverArtifacts(forProject: projectID)
        let second = try await provider.discoverArtifacts(forProject: projectID)

        #expect(first.first?.contentHash == second.first?.contentHash)
    }

    @Test("every discovered artifact belongs to the graphify provider")
    func everyDiscoveredArtifactBelongsToTheGraphifyProvider() async throws {
        let discovered = try await discover(["graphify-out/graph.json": "{}"])

        #expect(discovered.first?.artifact.provider == .graphify)
        #expect(discovered.first?.artifact.projectID == projectID)
    }

    @Test("the report yields knowledge and the graph yields none, because it is data")
    func theReportYieldsKnowledgeAndTheGraphYieldsNone() async throws {
        let workspace = try WorkspaceFixture.make([
            "graphify-out/graph.json": "{\n  \"directed\": false\n}",
            "graphify-out/GRAPH_REPORT.md": "# Graph Report - anchor\n\n## Corpus Check",
        ])
        let provider = GraphifyArtifactProvider(workspaceURL: workspace)
        var entriesByName: [String: [KnowledgeEntry]] = [:]
        for discovered in try await provider.discoverArtifacts(forProject: projectID) {
            entriesByName[discovered.artifact.name] =
                try await provider
                .classifyKnowledgeEntries(in: discovered)
        }

        #expect(entriesByName["graphify-out/graph.json"]?.isEmpty == true)
        #expect(entriesByName["graphify-out/GRAPH_REPORT.md"]?.count == 1)
        #expect(
            entriesByName["graphify-out/GRAPH_REPORT.md"]?.first?.summaryText
                == "# Graph Report - anchor"
        )
    }
}
