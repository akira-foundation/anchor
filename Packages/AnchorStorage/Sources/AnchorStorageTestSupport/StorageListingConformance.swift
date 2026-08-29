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
        try makeStorageObject("projects/anchor/small", contents: "anchor"),
        precondition: .none
    )
    try await provider.putObject(
        try makeStorageObject(
            "projects/anchor/large", contents: String(repeating: "anchor", count: 100)),
        precondition: .none
    )

    let sizes = try await provider.listObjects(withPrefix: nil)
        .sorted { $0.key.rawValue < $1.key.rawValue }
        .map(\.byteSize)

    #expect(sizes.count == 2)
    #expect(sizes.first ?? 0 > 0)
    #expect((sizes.first ?? 0) > (sizes.last ?? 0))
}
