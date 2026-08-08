import Testing

@testable import AnchorDomain

@Suite("Project identity")
struct ProjectTests {
    @Test("two projects with the same remote but different identifiers are distinct")
    func twoProjectsWithTheSameRemoteButDifferentIdentifiersAreDistinct() {
        let sharedRemote = "github.com/akira-foundation/anchor"
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
    func projectKeepsItsIdentityWhenItsDisplayNameChanges() {
        let projectID = ProjectID()
        let originalProject = Project(
            id: projectID,
            displayName: "Anchor",
            canonicalRepositoryRemote: "github.com/akira-foundation/anchor"
        )
        let renamedProject = Project(
            id: projectID,
            displayName: "Anchor Context Layer",
            canonicalRepositoryRemote: "github.com/akira-foundation/anchor"
        )

        #expect(originalProject.id == renamedProject.id)
        #expect(originalProject != renamedProject)
    }
}
