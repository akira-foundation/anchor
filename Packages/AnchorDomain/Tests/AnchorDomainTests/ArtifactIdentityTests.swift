import Foundation
import Testing

@testable import AnchorDomain

@Suite("Deriving an artifact identity")
struct ArtifactIdentityTests {
    private let projectID = ProjectID()

    @Test("the same project, provider and name always name the same artifact")
    func theSameProjectProviderAndNameAlwaysNameTheSameArtifact() {
        let first = ArtifactID.derived(
            projectID: projectID, provider: .superpowers, name: "docs/plans/00-index.md")
        let second = ArtifactID.derived(
            projectID: projectID, provider: .superpowers, name: "docs/plans/00-index.md")

        #expect(first == second)
    }

    @Test("a different name is a different artifact")
    func aDifferentNameIsADifferentArtifact() {
        let first = ArtifactID.derived(projectID: projectID, provider: .claude, name: "a.json")
        let second = ArtifactID.derived(projectID: projectID, provider: .claude, name: "b.json")

        #expect(first != second)
    }

    @Test("the same name in a different project is a different artifact")
    func theSameNameInADifferentProjectIsADifferentArtifact() {
        let mine = ArtifactID.derived(projectID: projectID, provider: .claude, name: "a.json")
        let theirs = ArtifactID.derived(projectID: ProjectID(), provider: .claude, name: "a.json")

        #expect(mine != theirs)
    }

    @Test("the same name from a different provider is a different artifact")
    func theSameNameFromADifferentProviderIsADifferentArtifact() {
        let claude = ArtifactID.derived(projectID: projectID, provider: .claude, name: "a.json")
        let codex = ArtifactID.derived(projectID: projectID, provider: .codex, name: "a.json")

        #expect(claude != codex)
    }

    @Test("the derived identity is a well formed identifier")
    func theDerivedIdentityIsAWellFormedIdentifier() throws {
        let derived = ArtifactID.derived(
            projectID: projectID, provider: .graphify, name: "graph.json")

        #expect(ArtifactID(rawValue: derived.rawValue) == derived)
    }
}
