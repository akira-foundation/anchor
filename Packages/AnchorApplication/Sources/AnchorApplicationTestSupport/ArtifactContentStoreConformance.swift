import AnchorApplication
import AnchorDomain
import Foundation
import Testing

public func verifyArtifactContentStoreContract(
    _ makeStore: @Sendable () async -> any ArtifactContentStore
) async throws {
    try await verifyStoredContentComesBackForItsRevision(makeStore)
    try await verifyContentOfAnUnknownRevisionIsAbsent(makeStore)
    try await verifyDroppingOneRevisionLeavesTheOthers(makeStore)
    try await verifyDroppingAnAbsentRevisionIsIdempotent(makeStore)
}

func verifyStoredContentComesBackForItsRevision(
    _ makeStore: @Sendable () async -> any ArtifactContentStore
) async throws {
    let store = await makeStore()
    let revisionID = RevisionID()

    try await store.storeContent(Data("anchor".utf8), forRevision: revisionID)

    #expect(try await store.content(forRevision: revisionID) == Data("anchor".utf8))
}

func verifyContentOfAnUnknownRevisionIsAbsent(
    _ makeStore: @Sendable () async -> any ArtifactContentStore
) async throws {
    let store = await makeStore()

    try await store.storeContent(Data("anchor".utf8), forRevision: RevisionID())

    #expect(try await store.content(forRevision: RevisionID()) == nil)
}

func verifyDroppingOneRevisionLeavesTheOthers(
    _ makeStore: @Sendable () async -> any ArtifactContentStore
) async throws {
    let store = await makeStore()
    let dropped = RevisionID()
    let kept = RevisionID()

    try await store.storeContent(Data("gone".utf8), forRevision: dropped)
    try await store.storeContent(Data("still here".utf8), forRevision: kept)
    try await store.dropContent(forRevision: dropped)

    #expect(try await store.content(forRevision: dropped) == nil)
    #expect(try await store.content(forRevision: kept) == Data("still here".utf8))
}

func verifyDroppingAnAbsentRevisionIsIdempotent(
    _ makeStore: @Sendable () async -> any ArtifactContentStore
) async throws {
    let store = await makeStore()

    try await store.dropContent(forRevision: RevisionID())
}
