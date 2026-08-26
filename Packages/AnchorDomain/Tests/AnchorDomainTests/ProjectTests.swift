import Testing

@testable import AnchorDomain

@Suite("Project identity")
struct ProjectTests {
    @Test("two projects with the same remote but different identifiers are distinct")
    func twoProjectsWithTheSameRemoteButDifferentIdentifiersAreDistinct() throws {
        let sharedRemote = try #require(
            CanonicalRepositoryRemote(rawValue: "github.com/akira-foundation/anchor"))
        let firstProject = Project(
            id: ProjectID(),
            displayName: "Anchor",
            canonicalRepositoryRemote: sharedRemote
        )
        let secondProject = Project(
            id: ProjectID(),
            displayName: "Anchor",
            canonicalRepositoryRemote: sharedRemote
        )

        #expect(firstProject != secondProject)
    }

    @Test("a project keeps its identity when its display name changes")
    func projectKeepsItsIdentityWhenItsDisplayNameChanges() throws {
        let anchorRemote = try #require(
            CanonicalRepositoryRemote(rawValue: "github.com/akira-foundation/anchor"))
        let projectID = ProjectID()
        let originalProject = Project(
            id: projectID,
            displayName: "Anchor",
            canonicalRepositoryRemote: anchorRemote
        )
        let renamedProject = Project(
            id: projectID,
            displayName: "Anchor Context Layer",
            canonicalRepositoryRemote: anchorRemote
        )

        #expect(originalProject.id == renamedProject.id)
        #expect(originalProject != renamedProject)
    }
}
