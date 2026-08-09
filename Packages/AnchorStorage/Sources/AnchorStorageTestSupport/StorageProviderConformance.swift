import AnchorDomain
import AnchorStorage
import Foundation
import Testing

public func verifyStorageProviderConformance<Provider: StorageProvider>(
    makeProvider: @Sendable () async -> Provider
) async throws {
    try await verifyStoredObjectIsReturnedByItsKey(makeProvider)
    try await verifyAbsentKeyReturnsNoObjectWhileOtherKeysExist(makeProvider)
    try await verifyOverwritingAKeyReturnsTheNewestContents(makeProvider)
    try await verifyOverwritingAKeyChangesItsVersionTag(makeProvider)
    try await verifyDeletedObjectLeavesNeitherContentsNorMetadata(makeProvider)
    try await verifyDeletingAnAbsentKeyIsIdempotent(makeProvider)
    try await verifyWriteReturnsMetadataThatMatchesASubsequentRead(makeProvider)
    try await verifyListingWithoutAPrefixReturnsEveryObject(makeProvider)
    try await verifyPrefixMatchesWholeSegmentsRatherThanCharacters(makeProvider)
    try await verifyMetadataReportsTheStoredByteSize(makeProvider)
    try await verifyVersionTagPreconditionRejectsAStaleTag(makeProvider)
    try await verifyVersionTagPreconditionAcceptsTheCurrentTag(makeProvider)
    try await verifyAbsencePreconditionRejectsAnExistingObject(makeProvider)
    try await verifyAbsencePreconditionAcceptsAnAbsentObject(makeProvider)
    try await verifyPreconditionFailureReportsTheCurrentVersionTag(makeProvider)
    try await verifyWritingReportsACreatedThenAnUpdatedChange(makeProvider)
    try await verifyDeletingReportsADeletedChange(makeProvider)
    try await verifyObservingFromACursorReplaysOnlyLaterChanges(makeProvider)
}

func makeStorageKey(_ rawValue: String) throws -> StorageKey {
    try #require(StorageKey(rawValue: rawValue))
}

func makeStorageObject(_ rawKey: String, contents: String) throws -> StorageObject {
    StorageObject(key: try makeStorageKey(rawKey), contents: Data(contents.utf8))
}

func collectChanges<Provider: StorageProvider>(
    from provider: Provider,
    after cursor: StorageCursor?,
    expecting expectedCount: Int
) async throws -> [StorageChange] {
    var collectedChanges: [StorageChange] = []

    guard expectedCount > 0 else { return collectedChanges }

    for try await change in provider.observeChanges(after: cursor) {
        collectedChanges.append(change)

        guard collectedChanges.count < expectedCount else { break }
    }

    return collectedChanges
}
