import AnchorDomain
import Testing

@testable import AnchorPersistence

private actor InMemoryProjectIdentifierStore: ProjectIdentifierStore {
    private var registeredProjectIdentifiers: [ProjectIdentifier] = []

    func storeRegisteredProjectIdentifier(_ projectIdentifier: ProjectIdentifier) async throws {
        guard !registeredProjectIdentifiers.contains(projectIdentifier) else { return }

        registeredProjectIdentifiers.append(projectIdentifier)
    }

    func loadRegisteredProjectIdentifiers() async throws -> [ProjectIdentifier] {
        registeredProjectIdentifiers
    }
}

@Suite("ProjectIdentifierStore contract")
struct ProjectIdentifierStoreContractTests {
    @Test("a stored project identifier is returned on load")
    func storedProjectIdentifierIsReturnedOnLoad() async throws {
        let expectedProjectIdentifier = ProjectIdentifier()
        let projectIdentifierStore = InMemoryProjectIdentifierStore()

        try await projectIdentifierStore.storeRegisteredProjectIdentifier(expectedProjectIdentifier)

        #expect(try await projectIdentifierStore.loadRegisteredProjectIdentifiers() == [expectedProjectIdentifier])
    }

    @Test("storing the same project identifier twice does not duplicate it")
    func storingTheSameProjectIdentifierTwiceDoesNotDuplicateIt() async throws {
        let repeatedProjectIdentifier = ProjectIdentifier()
        let projectIdentifierStore = InMemoryProjectIdentifierStore()

        try await projectIdentifierStore.storeRegisteredProjectIdentifier(repeatedProjectIdentifier)
        try await projectIdentifierStore.storeRegisteredProjectIdentifier(repeatedProjectIdentifier)

        #expect(try await projectIdentifierStore.loadRegisteredProjectIdentifiers().count == 1)
    }
}
