import AnchorDomain
import Testing

@testable import AnchorSearch

private struct StaticSearchQueryRunner: SearchQueryRunning {
    let matchingArtifactIdentifiersByQueryText: [String: [ArtifactIdentifier]]

    func findMatchingArtifactIdentifiers(forQueryText queryText: String) async throws -> [ArtifactIdentifier] {
        matchingArtifactIdentifiersByQueryText[queryText] ?? []
    }
}

@Suite("SearchQueryRunning contract")
struct SearchQueryRunningContractTests {
    @Test("a query with matches returns the matching artifact identifiers")
    func queryWithMatchesReturnsTheMatchingArtifactIdentifiers() async throws {
        let expectedArtifactIdentifier = ArtifactIdentifier()
        let searchQueryRunner = StaticSearchQueryRunner(
            matchingArtifactIdentifiersByQueryText: ["composition root": [expectedArtifactIdentifier]]
        )

        let matchingArtifactIdentifiers = try await searchQueryRunner
            .findMatchingArtifactIdentifiers(forQueryText: "composition root")

        #expect(matchingArtifactIdentifiers == [expectedArtifactIdentifier])
    }

    @Test("a query without matches returns no artifact identifiers")
    func queryWithoutMatchesReturnsNoArtifactIdentifiers() async throws {
        let searchQueryRunner = StaticSearchQueryRunner(matchingArtifactIdentifiersByQueryText: [:])

        #expect(try await searchQueryRunner.findMatchingArtifactIdentifiers(forQueryText: "absent").isEmpty)
    }
}
