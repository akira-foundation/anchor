import AnchorDomain
import AnchorStorage
import Foundation
import Testing

func verifyWritingReportsACreatedThenAnUpdatedChange<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storageKey = try makeStorageKey("projects/anchor/index")

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "first"),
        precondition: .none
    )
    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "second"),
        precondition: .none
    )

    let observedChanges = try await collectChanges(from: provider, after: nil, expecting: 2)

    #expect(observedChanges.map(\.kind) == [.created, .updated])
    #expect(observedChanges.allSatisfy { $0.key == storageKey })
}

func verifyDeletingReportsADeletedChange<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()
    let storedObject = try makeStorageObject("projects/anchor/index", contents: "anchor")

    try await provider.putObject(storedObject, precondition: .none)
    try await provider.deleteObject(for: storedObject.key)

    let observedChanges = try await collectChanges(from: provider, after: nil, expecting: 2)

    #expect(observedChanges.map(\.kind) == [.created, .deleted])
}

func verifyObservingFromACursorReplaysOnlyLaterChanges<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "first"),
        precondition: .none
    )
    try await provider.putObject(
        try makeStorageObject("devices/laptop", contents: "second"),
        precondition: .none
    )

    let allChanges = try await collectChanges(from: provider, after: nil, expecting: 2)
    let firstChange = try #require(allChanges.first)

    let laterChanges = try await collectChanges(
        from: provider,
        after: firstChange.cursor,
        expecting: 1
    )

    #expect(laterChanges.map(\.key.rawValue) == ["devices/laptop"])
}
