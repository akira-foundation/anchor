import AnchorDomain
import AnchorStorage
import AnchorStorageTestSupport
import Foundation
import Testing

@Suite("InMemoryStorageProvider conforms to the StorageProvider contract")
struct InMemoryStorageProviderTests {
    @Test("the in memory provider satisfies every contract expectation")
    func inMemoryProviderSatisfiesEveryContractExpectation() async throws {
        try await verifyStorageProviderConformance { InMemoryStorageProvider() }
    }
}
