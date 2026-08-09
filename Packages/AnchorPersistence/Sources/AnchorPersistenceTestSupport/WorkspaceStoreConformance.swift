import AnchorDomain
import AnchorPersistence
import Foundation
import Testing

public func verifyWorkspaceStoreConformance<Store: WorkspaceStore>(
    makeStore: @Sendable () async -> Store
) async throws {
    try await verifyStoredWorkspaceIsReturnedByItsIdentifier(makeStore)
    try await verifyUnknownIdentifierReturnsNoWorkspace(makeStore)
    try await verifyOnlyTheWorkspacesOfTheRequestedProjectAreReturned(makeStore)
    try await verifyAWorkspaceWithoutALocalRepositoryRoundTripsUnchanged(makeStore)
    try await verifyEveryWorkspaceOfAProjectIsReturned(makeStore)
}

private func makeWorkspace(projectID: ProjectID, localRepositoryURL: URL?) -> Workspace {
    Workspace(
        id: WorkspaceID(),
        projectID: projectID,
        deviceID: DeviceID(),
        localRepositoryURL: localRepositoryURL
    )
}

private func verifyStoredWorkspaceIsReturnedByItsIdentifier<Store: WorkspaceStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let workspaceStore = await makeStore()
    let expectedWorkspace = makeWorkspace(
        projectID: ProjectID(),
        localRepositoryURL: URL(filePath: "/Users/kid/Developer/anchor")
    )

    try await workspaceStore.storeWorkspace(expectedWorkspace)

    #expect(
        try await workspaceStore.loadWorkspace(withIdentifier: expectedWorkspace.id)
            == expectedWorkspace
    )
}

private func verifyUnknownIdentifierReturnsNoWorkspace<Store: WorkspaceStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let workspaceStore = await makeStore()

    try await workspaceStore.storeWorkspace(
        makeWorkspace(projectID: ProjectID(), localRepositoryURL: nil)
    )

    #expect(try await workspaceStore.loadWorkspace(withIdentifier: WorkspaceID()) == nil)
}

private func verifyOnlyTheWorkspacesOfTheRequestedProjectAreReturned<Store: WorkspaceStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let workspaceStore = await makeStore()
    let requestedProjectID = ProjectID()
    let matchingWorkspace = makeWorkspace(projectID: requestedProjectID, localRepositoryURL: nil)
    let otherWorkspace = makeWorkspace(projectID: ProjectID(), localRepositoryURL: nil)

    try await workspaceStore.storeWorkspace(matchingWorkspace)
    try await workspaceStore.storeWorkspace(otherWorkspace)

    #expect(
        try await workspaceStore.loadWorkspaces(forProject: requestedProjectID)
            == [matchingWorkspace]
    )
}

private func verifyAWorkspaceWithoutALocalRepositoryRoundTripsUnchanged<Store: WorkspaceStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let workspaceStore = await makeStore()
    let checkoutFreeWorkspace = makeWorkspace(projectID: ProjectID(), localRepositoryURL: nil)

    try await workspaceStore.storeWorkspace(checkoutFreeWorkspace)

    let loadedWorkspace = try #require(
        try await workspaceStore.loadWorkspace(withIdentifier: checkoutFreeWorkspace.id)
    )

    #expect(loadedWorkspace == checkoutFreeWorkspace)
    #expect(loadedWorkspace.localRepositoryURL == nil)
}

private func verifyEveryWorkspaceOfAProjectIsReturned<Store: WorkspaceStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let workspaceStore = await makeStore()
    let sharedProjectID = ProjectID()
    let laptopWorkspace = makeWorkspace(
        projectID: sharedProjectID,
        localRepositoryURL: URL(filePath: "/Users/kid/Developer/anchor")
    )
    let desktopWorkspace = makeWorkspace(
        projectID: sharedProjectID,
        localRepositoryURL: URL(filePath: "/Users/kid/Code/anchor-v2")
    )

    try await workspaceStore.storeWorkspace(laptopWorkspace)
    try await workspaceStore.storeWorkspace(desktopWorkspace)

    let loadedIdentifiers = try await Set(
        workspaceStore.loadWorkspaces(forProject: sharedProjectID).map(\.id)
    )

    #expect(loadedIdentifiers == [laptopWorkspace.id, desktopWorkspace.id])
}
