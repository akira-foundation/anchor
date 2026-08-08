import AnchorDomain
import AnchorStorage
import Foundation
import Testing

public func verifyStorageProviderConformance<Provider: StorageProvider>(
    makeProvider: @Sendable () async -> Provider
) async throws {
    try await verifyStoredObjectIsReturnedByItsKey(makeProvider)
    try await verifyAbsentKeyReturnsNoObject(makeProvider)
    try await verifyOverwritingAKeyReturnsTheNewestContents(makeProvider)
    try await verifyDeletedObjectIsNoLongerReturned(makeProvider)
    try await verifyDeletingAnAbsentKeyReportsTheMissingObject(makeProvider)
    try await verifyListingWithoutAPrefixReturnsEveryObject(makeProvider)
    try await verifyListingWithAPrefixReturnsOnlyMatchingObjects(makeProvider)
    try await verifyMetadataReportsTheStoredByteSize(makeProvider)
    try await verifyConditionalWriteWithAStaleVersionTagIsRejected(makeProvider)
    try await verifyConditionalWriteWithTheCurrentVersionTagSucceeds(makeProvider)
    try await verifyConditionalWriteAgainstAnAbsentKeyIsRejected(makeProvider)
}

private func makeStorageKey(_ rawValue: String) throws -> StorageKey {
    try #require(StorageKey(rawValue: rawValue))
}

private func makeStorageObject(
    _ rawKey: String,
    contents: String,
    expectedVersionTag: StorageVersionTag? = nil
) throws -> StorageObject {
    StorageObject(
        key: try makeStorageKey(rawKey),
        contents: Data(contents.utf8),
        expectedVersionTag: expectedVersionTag
    )
}

private func verifyStoredObjectIsReturnedByItsKey<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storedObject = try makeStorageObject("projects/anchor/index", contents: "anchor")

    try await provider.putObject(storedObject)

    #expect(try await provider.object(for: storedObject.key)?.contents == storedObject.contents)
}

private func verifyAbsentKeyReturnsNoObject<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    #expect(try await provider.object(for: try makeStorageKey("projects/absent")) == nil)
}

private func verifyOverwritingAKeyReturnsTheNewestContents<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(try makeStorageObject("projects/anchor/index", contents: "first"))
    try await provider.putObject(try makeStorageObject("projects/anchor/index", contents: "second"))

    let storedContents = try await provider.object(
        for: try makeStorageKey("projects/anchor/index"))?
        .contents

    #expect(storedContents == Data("second".utf8))
}

private func verifyDeletedObjectIsNoLongerReturned<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storedObject = try makeStorageObject("projects/anchor/index", contents: "anchor")

    try await provider.putObject(storedObject)
    try await provider.deleteObject(for: storedObject.key)

    #expect(try await provider.object(for: storedObject.key) == nil)
}

private func verifyDeletingAnAbsentKeyReportsTheMissingObject<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let absentKey = try makeStorageKey("projects/absent")

    await #expect(throws: StorageFailure.objectNotFound(absentKey)) {
        try await provider.deleteObject(for: absentKey)
    }
}

private func verifyListingWithoutAPrefixReturnsEveryObject<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(try makeStorageObject("projects/anchor/index", contents: "a"))
    try await provider.putObject(try makeStorageObject("devices/laptop", contents: "b"))

    let listedKeys = try await provider.listObjects(withPrefix: nil).map(\.key.rawValue)

    #expect(Set(listedKeys) == ["projects/anchor/index", "devices/laptop"])
}

private func verifyListingWithAPrefixReturnsOnlyMatchingObjects<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(try makeStorageObject("projects/anchor/index", contents: "a"))
    try await provider.putObject(try makeStorageObject("devices/laptop", contents: "b"))

    let listedKeys =
        try await provider
        .listObjects(withPrefix: try makeStorageKey("projects"))
        .map(\.key.rawValue)

    #expect(listedKeys == ["projects/anchor/index"])
}

private func verifyMetadataReportsTheStoredByteSize<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storedObject = try makeStorageObject("projects/anchor/index", contents: "anchor")

    try await provider.putObject(storedObject)

    #expect(try await provider.listObjects(withPrefix: nil).first?.byteSize == 6)
}

private func verifyConditionalWriteWithAStaleVersionTagIsRejected<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storageKey = try makeStorageKey("projects/anchor/index")

    try await provider.putObject(try makeStorageObject("projects/anchor/index", contents: "first"))

    await #expect(throws: StorageFailure.versionConflict(storageKey)) {
        try await provider.putObject(
            try makeStorageObject(
                "projects/anchor/index",
                contents: "second",
                expectedVersionTag: StorageVersionTag(rawValue: "stale")
            )
        )
    }
}

private func verifyConditionalWriteWithTheCurrentVersionTagSucceeds<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storageKey = try makeStorageKey("projects/anchor/index")

    try await provider.putObject(try makeStorageObject("projects/anchor/index", contents: "first"))

    let currentVersionTag = try #require(
        try await provider.listObjects(withPrefix: nil).first?.versionTag
    )

    try await provider.putObject(
        try makeStorageObject(
            "projects/anchor/index",
            contents: "second",
            expectedVersionTag: currentVersionTag
        )
    )

    #expect(try await provider.object(for: storageKey)?.contents == Data("second".utf8))
}

private func verifyConditionalWriteAgainstAnAbsentKeyIsRejected<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storageKey = try makeStorageKey("projects/absent")

    await #expect(throws: StorageFailure.versionConflict(storageKey)) {
        try await provider.putObject(
            try makeStorageObject(
                "projects/absent",
                contents: "anchor",
                expectedVersionTag: StorageVersionTag(rawValue: "any")
            )
        )
    }
}
