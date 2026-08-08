import Foundation
import Testing

@testable import AnchorStorage

private actor InMemoryStorageProvider: StorageProvider {
    private var storedDataByRelativePath: [String: Data] = [:]

    func writeStoredData(_ storedData: Data, toRelativePath relativePath: String) async throws {
        storedDataByRelativePath[relativePath] = storedData
    }

    func readStoredData(atRelativePath relativePath: String) async throws -> Data {
        guard let storedData = storedDataByRelativePath[relativePath] else {
            throw StorageReadFailure.noStoredDataAtRelativePath(relativePath)
        }

        return storedData
    }
}

@Suite("StorageProvider contract")
struct StorageProviderContractTests {
    @Test("written data is returned by a read at the same relative path")
    func writtenDataIsReturnedByAReadAtTheSameRelativePath() async throws {
        let expectedStoredData = Data("anchor".utf8)
        let storageProvider = InMemoryStorageProvider()

        try await storageProvider.writeStoredData(expectedStoredData, toRelativePath: "projects/index")

        #expect(try await storageProvider.readStoredData(atRelativePath: "projects/index") == expectedStoredData)
    }

    @Test("reading an absent relative path reports the missing path")
    func readingAnAbsentRelativePathReportsTheMissingPath() async throws {
        let storageProvider = InMemoryStorageProvider()

        await #expect(throws: StorageReadFailure.noStoredDataAtRelativePath("projects/index")) {
            try await storageProvider.readStoredData(atRelativePath: "projects/index")
        }
    }
}
