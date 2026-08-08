import AnchorDomain
import AnchorPersistence
import Testing

public func verifyProjectStoreConformance<Store: ProjectStore>(
    makeStore: @Sendable () async -> Store
) async throws {
    try await verifyStoredProjectIsReturnedByItsIdentifier(makeStore)
    try await verifyUnknownIdentifierReturnsNoProject(makeStore)
    try await verifyStoringAProjectAgainReplacesItRatherThanDuplicatingIt(makeStore)
    try await verifyEveryStoredProjectIsReturned(makeStore)
}

private func makeProject(displayName: String) -> Project {
    Project(
        id: ProjectID(),
        displayName: displayName,
        canonicalRepositoryRemote: "github.com/akira-foundation/\(displayName.lowercased())"
    )
}

private func verifyStoredProjectIsReturnedByItsIdentifier<Store: ProjectStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let projectStore = await makeStore()
    let expectedProject = makeProject(displayName: "Anchor")

    try await projectStore.storeProject(expectedProject)

    #expect(
        try await projectStore.loadProject(withIdentifier: expectedProject.id) == expectedProject)
}

private func verifyUnknownIdentifierReturnsNoProject<Store: ProjectStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let projectStore = await makeStore()

    try await projectStore.storeProject(makeProject(displayName: "Anchor"))

    #expect(try await projectStore.loadProject(withIdentifier: ProjectID()) == nil)
}

private func verifyStoringAProjectAgainReplacesItRatherThanDuplicatingIt<Store: ProjectStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let projectStore = await makeStore()
    let originalProject = makeProject(displayName: "Anchor")
    let renamedProject = Project(
        id: originalProject.id,
        displayName: "Anchor Context Layer",
        canonicalRepositoryRemote: originalProject.canonicalRepositoryRemote
    )

    try await projectStore.storeProject(originalProject)
    try await projectStore.storeProject(renamedProject)

    #expect(try await projectStore.loadAllProjects() == [renamedProject])
}

private func verifyEveryStoredProjectIsReturned<Store: ProjectStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let projectStore = await makeStore()
    let firstProject = makeProject(displayName: "Anchor")
    let secondProject = makeProject(displayName: "Dotsync")

    try await projectStore.storeProject(firstProject)
    try await projectStore.storeProject(secondProject)

    let loadedIdentifiers = try await Set(projectStore.loadAllProjects().map(\.id))

    #expect(loadedIdentifiers == [firstProject.id, secondProject.id])
}
