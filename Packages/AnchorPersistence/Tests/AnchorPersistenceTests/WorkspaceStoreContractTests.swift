import AnchorDomain
import Foundation
import Testing

@testable import AnchorPersistence

private actor InMemoryWorkspaceStore: WorkspaceStore {
    private var workspacesByIdentifier: [WorkspaceID: Workspace] = [:]

    func storeWorkspace(_ workspace: Workspace) async throws {
        workspacesByIdentifier[workspace.id] = workspace
    }

    func loadWorkspace(withIdentifier identifier: WorkspaceID) async throws -> Workspace? {
        workspacesByIdentifier[identifier]
    }

    func loadWorkspaces(forProject projectIdentifier: ProjectID) async throws -> [Workspace] {
        workspacesByIdentifier.values
            .filter { $0.projectID == projectIdentifier }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }
}

@Suite("WorkspaceStore contract")
struct WorkspaceStoreContractTests {
    @Test("a stored workspace is returned by its identifier")
    func storedWorkspaceIsReturnedByItsIdentifier() async throws {
        let workspaceStore = InMemoryWorkspaceStore()
        let expectedWorkspace = Workspace(
            id: WorkspaceID(),
            projectID: ProjectID(),
            deviceID: DeviceID(),
            localRepositoryURL: URL(filePath: "/Users/kid/Developer/anchor")
        )

        try await workspaceStore.storeWorkspace(expectedWorkspace)

        #expect(
            try await workspaceStore.loadWorkspace(withIdentifier: expectedWorkspace.id)
                == expectedWorkspace
        )
    }

    @Test("only the workspaces of the requested project are returned")
    func onlyTheWorkspacesOfTheRequestedProjectAreReturned() async throws {
        let workspaceStore = InMemoryWorkspaceStore()
        let requestedProjectID = ProjectID()
        let matchingWorkspace = Workspace(
            id: WorkspaceID(),
            projectID: requestedProjectID,
            deviceID: DeviceID(),
            localRepositoryURL: nil
        )
        let otherWorkspace = Workspace(
            id: WorkspaceID(),
            projectID: ProjectID(),
            deviceID: DeviceID(),
            localRepositoryURL: nil
        )

        try await workspaceStore.storeWorkspace(matchingWorkspace)
        try await workspaceStore.storeWorkspace(otherWorkspace)

        #expect(
            try await workspaceStore.loadWorkspaces(forProject: requestedProjectID)
                == [matchingWorkspace]
        )
    }

    @Test("a workspace without a local repository is stored and returned unchanged")
    func workspaceWithoutALocalRepositoryIsStoredAndReturnedUnchanged() async throws {
        let workspaceStore = InMemoryWorkspaceStore()
        let checkoutFreeWorkspace = Workspace(
            id: WorkspaceID(),
            projectID: ProjectID(),
            deviceID: DeviceID(),
            localRepositoryURL: nil
        )

        try await workspaceStore.storeWorkspace(checkoutFreeWorkspace)

        let loadedWorkspace =
            try await workspaceStore
            .loadWorkspace(withIdentifier: checkoutFreeWorkspace.id)

        #expect(loadedWorkspace?.localRepositoryURL == nil)
    }
}
