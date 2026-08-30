import AnchorDomain
import Foundation
import Testing

@testable import AnchorProvider

@Suite("Classification reads the bytes it was given")
struct ClassificationContentTests {
    @Test("the digest and the summary describe the same bytes")
    func theDigestAndTheSummaryDescribeTheSameBytes() async throws {
        let content = Data("# The title that was read\nbody".utf8)
        let artifact = try #require(
            Artifact(
                id: ArtifactID(), projectID: ProjectID(), provider: .superpowers, name: "plan.md")
        )
        let discovered = DiscoveredArtifact(
            artifact: artifact, contentHash: ContentHash.digest(of: content)
        )
        let classifier = FirstLineClassifier()

        let entries = try await classifier.classifyKnowledgeEntries(
            in: discovered, content: content)

        #expect(entries.first?.summaryText == "# The title that was read")
        #expect(discovered.contentHash == ContentHash.digest(of: content))
    }

    @Test("a file rewritten after discovery cannot change what the classification saw")
    func aFileRewrittenAfterDiscoveryCannotChangeWhatTheClassificationSaw() async throws {
        let discoveredContent = Data("# As discovered\nbody".utf8)
        let artifact = try #require(
            Artifact(
                id: ArtifactID(), projectID: ProjectID(), provider: .superpowers, name: "plan.md")
        )
        let discovered = DiscoveredArtifact(
            artifact: artifact, contentHash: ContentHash.digest(of: discoveredContent)
        )

        let entries = try await FirstLineClassifier()
            .classifyKnowledgeEntries(in: discovered, content: discoveredContent)

        #expect(entries.first?.summaryText == "# As discovered")
    }
}

private struct FirstLineClassifier: ArtifactClassifying {
    func classifyKnowledgeEntries(
        in discoveredArtifact: DiscoveredArtifact,
        content: Data
    ) async throws -> [KnowledgeEntry] {
        let firstLine = String(decoding: content, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let firstLine else { return [] }

        return [
            KnowledgeEntry(
                id: KnowledgeEntryID(),
                projectID: discoveredArtifact.artifact.projectID,
                kind: .summary,
                summaryText: firstLine,
                source: .artifact(discoveredArtifact.artifact.id),
                sourceContentHash: ContentHash.digest(of: Data("source".utf8)),
                createdAt: Date(timeIntervalSince1970: 0)
            )
        ]
    }
}
