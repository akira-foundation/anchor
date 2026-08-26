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

private func makeProject(displayName: String) throws -> Project {
    let repositoryRemote = try #require(
        CanonicalRepositoryRemote(
            gitRemote: "github.com/akira-foundation/\(displayName.lowercased())")
    )

    return Project(
        id: ProjectID(), displayName: displayName, canonicalRepositoryRemote: repositoryRemote)
}

private func verifyStoredProjectIsReturnedByItsIdentifier<Store: ProjectStore>(
    _ makeStore: @Sendable () async -> Store
) async throws {
    let projectStore = await makeStore()
    let expectedProject = try makeProject(displayName: "Anchor")

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
    let originalProject = try makeProject(displayName: "Anchor")
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
    let firstProject = try makeProject(displayName: "Anchor")
    let secondProject = try makeProject(displayName: "Dotsync")

    try await projectStore.storeProject(firstProject)
    try await projectStore.storeProject(secondProject)

    let loadedIdentifiers = try await Set(projectStore.loadAllProjects().map(\.id))

    #expect(loadedIdentifiers == [firstProject.id, secondProject.id])
}
