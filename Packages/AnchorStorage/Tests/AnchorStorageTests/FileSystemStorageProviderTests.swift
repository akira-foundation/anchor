import AnchorDomain
import AnchorStorage
import AnchorStorageTestSupport
import Foundation
import Testing

@Suite("File system storage provider")
struct FileSystemStorageProviderTests {
    @Test("it honours the storage provider contract")
    func itHonoursTheStorageProviderContract() async throws {
        try await verifyStorageProviderConformance {
            FileSystemStorageProvider(
                rootURL: FileManager.default.temporaryDirectory
                    .appending(path: "anchor-storage-\(UUID().uuidString)")
            )
        }
    }

    @Test("what it writes survives a new provider over the same directory")
    func whatItWritesSurvivesANewProviderOverTheSameDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "anchor-storage-\(UUID().uuidString)")
        let key = try #require(StorageKey(rawValue: "projects/anchor/index"))
        let contents = Data("remembered".utf8)

        try await FileSystemStorageProvider(rootURL: root)
            .putObject(StorageObject(key: key, contents: contents), precondition: .none)

        let reopened = FileSystemStorageProvider(rootURL: root)
        let stored = try await reopened.object(for: key)

        #expect(stored?.object.contents == contents)
    }
}
