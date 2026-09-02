import AnchorDomain
import Foundation
import Testing

@testable import AnchorStorage

@Suite("Storing files where the folder name is spelled the way people spell folders")
struct FileSystemStorageProviderPathTests {
    private let storageKey = StorageKey(rawValue: "revisions/one/two")!
    private let contents = Data("a revision".utf8)

    private func rootURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-\(UUID().uuidString)")
            .appending(path: name)
    }

    @Test(
        "a folder whose name has a space is a folder like any other",
        arguments: ["Application Support", "plain", "a folder + a sign", "café"]
    )
    func folderWhoseNameHasASpaceIsAFolderLikeAnyOther(folderName: String) async throws {
        let root = rootURL(named: folderName)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let storage = FileSystemStorageProvider(rootURL: root)
        let written = try await storage.putObject(
            StorageObject(key: storageKey, contents: contents), precondition: .none)

        #expect(written.byteSize == contents.count)
        #expect(try await storage.object(for: storageKey)?.object.contents == contents)
        #expect(try await storage.listObjects(withPrefix: nil).map(\.key) == [storageKey])
    }

    @Test("a precondition still holds when the folder name has a space")
    func preconditionStillHoldsWhenFolderNameHasASpace() async throws {
        let root = rootURL(named: "Application Support")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let storage = FileSystemStorageProvider(rootURL: root)
        try await storage.putObject(
            StorageObject(key: storageKey, contents: contents), precondition: .objectIsAbsent)

        await #expect(throws: StorageFailure.self) {
            try await storage.putObject(
                StorageObject(key: storageKey, contents: contents), precondition: .objectIsAbsent)
        }
    }

    @Test("deleting works when the folder name has a space")
    func deletingWorksWhenFolderNameHasASpace() async throws {
        let root = rootURL(named: "Application Support")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let storage = FileSystemStorageProvider(rootURL: root)
        try await storage.putObject(
            StorageObject(key: storageKey, contents: contents), precondition: .none)
        try await storage.deleteObject(for: storageKey)

        #expect(try await storage.object(for: storageKey) == nil)
        #expect(try await storage.listObjects(withPrefix: nil).isEmpty)
    }
}
