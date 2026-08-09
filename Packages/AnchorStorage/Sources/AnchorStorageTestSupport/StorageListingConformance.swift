import AnchorDomain
import AnchorStorage
import Foundation
import Testing

func verifyListingWithoutAPrefixReturnsEveryObject<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "a"),
        precondition: .none
    )
    try await provider.putObject(
        try makeStorageObject("devices/laptop", contents: "b"),
        precondition: .none
    )

    let listedKeys = try await provider.listObjects(withPrefix: nil).map(\.key.rawValue)

    #expect(Set(listedKeys) == ["projects/anchor/index", "devices/laptop"])
}

func verifyPrefixMatchesWholeSegmentsRatherThanCharacters<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "a"),
        precondition: .none
    )
    try await provider.putObject(
        try makeStorageObject("projects-archive/secret", contents: "b"),
        precondition: .none
    )
    try await provider.putObject(
        try makeStorageObject("projects", contents: "c"),
        precondition: .none
    )

    let listedKeys =
        try await provider
        .listObjects(withPrefix: try makeStorageKey("projects"))
        .map(\.key.rawValue)

    #expect(Set(listedKeys) == ["projects", "projects/anchor/index"])
}

func verifyMetadataReportsTheStoredByteSize<Provider: StorageProvider>(
    _ makeProvider: @Sendable () async -> Provider
) async throws {
    let provider = await makeProvider()

    try await provider.putObject(
        try makeStorageObject("projects/anchor/index", contents: "anchor"),
        precondition: .none
    )

    #expect(try await provider.listObjects(withPrefix: nil).first?.byteSize == 6)
}
