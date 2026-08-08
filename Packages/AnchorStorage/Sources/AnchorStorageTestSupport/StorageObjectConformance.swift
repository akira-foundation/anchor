import AnchorDomain
import AnchorStorage
import Foundation
import Testing

func verifyStoredObjectIsReturnedByItsKey<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storedObject = try makeStorageObject("projects/anchor/index", contents: "anchor")

    try await provider.putObject(storedObject, precondition: .none)

    let readObject = try #require(try await provider.object(for: storedObject.key))

    #expect(readObject.object.contents == storedObject.contents)
    #expect(readObject.metadata.key == storedObject.key)
}

func verifyAbsentKeyReturnsNoObjectWhileOtherKeysExist<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "anchor"),
        precondition: .none
    )

    #expect(try await provider.object(for: try makeStorageKey("projects/absent")) == nil)
}

func verifyOverwritingAKeyReturnsTheNewestContents<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "first"),
        precondition: .none
    )
    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "second"),
        precondition: .none
    )

    let readObject = try #require(
        try await provider.object(for: try makeStorageKey("projects/anchor/index"))
    )

    #expect(readObject.object.contents == Data("second".utf8))
}

func verifyOverwritingAKeyChangesItsVersionTag<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storageKey = try makeStorageKey("projects/anchor/index")

    let firstMetadata = try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "first"),
        precondition: .none
    )
    let secondMetadata = try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "second"),
        precondition: .none
    )

    #expect(firstMetadata.versionTag != secondMetadata.versionTag)
    #expect(
        try await provider.object(for: storageKey)?.metadata.versionTag == secondMetadata.versionTag
    )
}

func verifyDeletedObjectLeavesNeitherContentsNorMetadata<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storedObject = try makeStorageObject("projects/anchor/index", contents: "anchor")

    try await provider.putObject(storedObject, precondition: .none)

    #expect(try await provider.object(for: storedObject.key) != nil)

    try await provider.deleteObject(for: storedObject.key)

    #expect(try await provider.object(for: storedObject.key) == nil)
    #expect(try await provider.listObjects(withPrefix: nil).isEmpty)
}

func verifyDeletingAnAbsentKeyIsIdempotent<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let absentKey = try makeStorageKey("projects/absent")

    try await provider.deleteObject(for: absentKey)
    try await provider.deleteObject(for: absentKey)

    #expect(try await provider.object(for: absentKey) == nil)
}

func verifyWriteReturnsMetadataThatMatchesASubsequentRead<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storedObject = try makeStorageObject("projects/anchor/index", contents: "anchor")

    let writtenMetadata = try await provider.putObject(storedObject, precondition: .none)
    let readObject = try #require(try await provider.object(for: storedObject.key))

    #expect(readObject.metadata == writtenMetadata)
}
