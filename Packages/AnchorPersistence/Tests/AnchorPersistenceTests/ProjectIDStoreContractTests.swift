import AnchorDomain
import Testing

@testable import AnchorPersistence

private actor InMemoryProjectIDStore: ProjectIDStore {
    private var registeredProjectIDs: [ProjectID] = []

    func storeRegisteredProjectID(_ projectID: ProjectID) async throws {
        guard !registeredProjectIDs.contains(projectID) else { return }

        registeredProjectIDs.append(projectID)
    }

    func loadRegisteredProjectIDs() async throws -> [ProjectID] {
        registeredProjectIDs
    }
}

@Suite("ProjectIDStore contract")
struct ProjectIDStoreContractTests {
    @Test("a stored project identifier is returned on load")
    func storedProjectIDIsReturnedOnLoad() async throws {
        let expectedProjectID = ProjectID()
        let projectIDStore = InMemoryProjectIDStore()

        try await projectIDStore.storeRegisteredProjectID(expectedProjectID)

        #expect(try await projectIDStore.loadRegisteredProjectIDs() == [expectedProjectID])
    }

    @Test("storing the same project identifier twice does not duplicate it")
    func storingTheSameProjectIDTwiceDoesNotDuplicateIt() async throws {
        let repeatedProjectID = ProjectID()
        let projectIDStore = InMemoryProjectIDStore()

        try await projectIDStore.storeRegisteredProjectID(repeatedProjectID)
        try await projectIDStore.storeRegisteredProjectID(repeatedProjectID)

        #expect(try await projectIDStore.loadRegisteredProjectIDs().count == 1)
    }
}
