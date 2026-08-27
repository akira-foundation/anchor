import Foundation
import Testing

@testable import AnchorDomain

@Suite("Artifact retention")
struct ArtifactRetentionTests {
    private func makeArtifact(retention: ArtifactRetention? = nil) throws -> Artifact {
        let artifact =
            retention.map {
                Artifact(
                    id: ArtifactID(), projectID: ProjectID(), provider: .graphify,
                    name: "graphify-out/graph.json", retention: $0
                )
            }
            ?? Artifact(
                id: ArtifactID(), projectID: ProjectID(), provider: .superpowers,
                name: "docs/superpowers/plans/00-indice.md"
            )

        return try #require(artifact)
    }

    @Test("an artifact keeps its full history unless it says otherwise")
    func anArtifactKeepsItsFullHistoryUnlessItSaysOtherwise() throws {
        #expect(try makeArtifact().retention == .fullHistory)
    }

    @Test("a derivable artifact can ask for its latest revision only")
    func aDerivableArtifactCanAskForItsLatestRevisionOnly() throws {
        #expect(try makeArtifact(retention: .latestRevisionOnly).retention == .latestRevisionOnly)
    }

    @Test("retention survives an encode and decode round trip")
    func retentionSurvivesAnEncodeAndDecodeRoundTrip() throws {
        let artifact = try makeArtifact(retention: .latestRevisionOnly)
        let decoded = try JSONDecoder().decode(Artifact.self, from: JSONEncoder().encode(artifact))

        #expect(decoded.retention == .latestRevisionOnly)
    }

    @Test("a payload written before retention existed keeps its full history")
    func aPayloadWrittenBeforeRetentionExistedKeepsItsFullHistory() throws {
        let encoded = Data(
            """
            {"id":"\(ArtifactID().rawValue)","projectID":"\(ProjectID().rawValue)",\
            "provider":"superpowers","name":"docs/superpowers/plans/00-indice.md"}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(Artifact.self, from: encoded)

        #expect(decoded.retention == .fullHistory)
    }

    @Test("retention does not change what makes two artifacts equal in identity")
    func retentionDoesNotChangeIdentity() throws {
        let artifactID = ArtifactID()
        let projectID = ProjectID()
        let kept = try #require(
            Artifact(
                id: artifactID, projectID: projectID, provider: .graphify,
                name: "graphify-out/graph.json")
        )
        let trimmed = try #require(
            Artifact(
                id: artifactID, projectID: projectID, provider: .graphify,
                name: "graphify-out/graph.json", retention: .latestRevisionOnly
            )
        )

        #expect(kept.id == trimmed.id)
        #expect(kept != trimmed)
    }
}
