import AnchorDomain
import AnchorStorage
import Foundation
import Testing

func verifyVersionTagPreconditionRejectsAStaleTag<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "first"),
        precondition: .none
    )

    await #expect(throws: StorageFailure.self) {
        try await provider.putObject(
            try makeStorageObject("projects/anchor/index", contents: "second"),
            precondition: .versionTagMatches(StorageVersionTag(rawValue: "stale"))
        )
    }

    let readObject = try #require(
        try await provider.object(for: try makeStorageKey("projects/anchor/index"))
    )

    #expect(readObject.object.contents == Data("first".utf8))
}

func verifyVersionTagPreconditionAcceptsTheCurrentTag<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storageKey = try makeStorageKey("projects/anchor/index")

    let firstMetadata = try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "first"),
        precondition: .none
    )

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "second"),
        precondition: .versionTagMatches(firstMetadata.versionTag)
    )

    #expect(try await provider.object(for: storageKey)?.object.contents == Data("second".utf8))
}

func verifyAbsencePreconditionRejectsAnExistingObject<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "first"),
        precondition: .none
    )

    await #expect(throws: StorageFailure.self) {
        try await provider.putObject(
            try makeStorageObject("projects/anchor/index", contents: "second"),
            precondition: .objectIsAbsent
        )
    }
}

func verifyAbsencePreconditionAcceptsAnAbsentObject<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storageKey = try makeStorageKey("projects/anchor/index")

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "first"),
        precondition: .objectIsAbsent
    )

    #expect(try await provider.object(for: storageKey)?.object.contents == Data("first".utf8))
}

func verifyPreconditionFailureReportsTheCurrentVersionTag<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storageKey = try makeStorageKey("projects/anchor/index")

    let writtenMetadata = try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "first"),
        precondition: .none
    )

    await #expect(
        throws: StorageFailure.preconditionFailed(
            storageKey,
            currentVersionTag: writtenMetadata.versionTag
        )
    ) {
        try await provider.putObject(
            try makeStorageObject("projects/anchor/index", contents: "second"),
            precondition: .versionTagMatches(StorageVersionTag(rawValue: "stale"))
        )
    }
}
