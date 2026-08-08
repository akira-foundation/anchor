import AnchorDomain
import Testing

@testable import AnchorSearch

private struct StaticSearchQueryRunner: SearchQueryRunning {
    let matchingArtifactIDsByQueryText: [String: [ArtifactID]]

    func findMatchingArtifactIDs(forQueryText queryText: String) async throws -> [ArtifactID] {
        matchingArtifactIDsByQueryText[queryText] ?? []
    }
}

@Suite("SearchQueryRunning contract")
struct SearchQueryRunningContractTests {
    @Test("a query with matches returns the matching artifact identifiers")
    func queryWithMatchesReturnsTheMatchingArtifactIDs() async throws {
        let expectedArtifactID = ArtifactID()
        let searchQueryRunner = StaticSearchQueryRunner(
            matchingArtifactIDsByQueryText: ["composition root": [expectedArtifactID]]
        )

        let matchingArtifactIDs = try await searchQueryRunner
            .findMatchingArtifactIDs(forQueryText: "composition root")

        #expect(matchingArtifactIDs == [expectedArtifactID])
    }

    @Test("a query without matches returns no artifact identifiers")
    func queryWithoutMatchesReturnsNoArtifactIDs() async throws {
        let searchQueryRunner = StaticSearchQueryRunner(matchingArtifactIDsByQueryText: [:])

        #expect(try await searchQueryRunner.findMatchingArtifactIDs(forQueryText: "absent").isEmpty)
    }
}
