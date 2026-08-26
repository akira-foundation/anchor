import Foundation
import Testing

@testable import AnchorDomain

@Suite("Artifact")
struct ArtifactTests {
    @Test("an artifact keeps its identity when its name changes")
    func anArtifactKeepsItsIdentityWhenItsNameChanges() throws {
        let artifactID = ArtifactID()
        let projectID = ProjectID()
        let original = try #require(
            Artifact(
                id: artifactID, projectID: projectID, provider: .superpowers, name: "commit-guard")
        )
        let renamed = try #require(
            Artifact(
                id: artifactID, projectID: projectID, provider: .superpowers, name: "commit-gate")
        )

        #expect(original.id == renamed.id)
        #expect(original != renamed)
    }

    @Test("two artifacts with the same name in one project stay distinct")
    func twoArtifactsWithTheSameNameInOneProjectStayDistinct() throws {
        let projectID = ProjectID()
        let first = try #require(
            Artifact(id: ArtifactID(), projectID: projectID, provider: .claude, name: "session")
        )
        let second = try #require(
            Artifact(id: ArtifactID(), projectID: projectID, provider: .claude, name: "session")
        )

        #expect(first != second)
    }

    @Test("an artifact belongs to one provider")
    func anArtifactBelongsToOneProvider() throws {
        let artifact = try #require(
            Artifact(id: ArtifactID(), projectID: ProjectID(), provider: .graphify, name: "graph")
        )

        #expect(artifact.provider == .graphify)
    }

    @Test(
        "a name that is empty or only whitespace is rejected",
        arguments: ["", " ", "\t", "\n", "   \n  "]
    )
    func aNameThatIsEmptyOrOnlyWhitespaceIsRejected(_ name: String) {
        #expect(
            Artifact(id: ArtifactID(), projectID: ProjectID(), provider: .codex, name: name) == nil)
    }

    @Test("a name is kept exactly as given once it is accepted")
    func aNameIsKeptExactlyAsGivenOnceItIsAccepted() throws {
        let artifact = try #require(
            Artifact(
                id: ArtifactID(), projectID: ProjectID(), provider: .codex, name: "review agent")
        )

        #expect(artifact.name == "review agent")
    }

    @Test("an artifact survives an encode and decode round trip")
    func anArtifactSurvivesAnEncodeAndDecodeRoundTrip() throws {
        let artifact = try #require(
            Artifact(
                id: ArtifactID(), projectID: ProjectID(), provider: .superpowers,
                name: "commit-guard")
        )
        let decoded = try JSONDecoder().decode(Artifact.self, from: JSONEncoder().encode(artifact))

        #expect(decoded == artifact)
    }

    @Test("an artifact with an empty name is rejected on decoding")
    func anArtifactWithAnEmptyNameIsRejectedOnDecoding() {
        let encoded = Data(
            """
            {"id":"\(ArtifactID().rawValue)","projectID":"\(ProjectID().rawValue)",\
            "provider":"claude","name":"  "}
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Artifact.self, from: encoded)
        }
    }
}
