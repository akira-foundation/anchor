import AnchorDomain
import AnchorStorage
import Foundation

public struct CloudRecordDraft: Sendable, Hashable {
    public let name: String
    public let key: StorageKey
    public let contents: Data

    public init(name: String, key: StorageKey, contents: Data) {
        self.name = name
        self.key = key
        self.contents = contents
    }
}

public struct CloudRecordSnapshot: Sendable, Hashable {
    public let name: String
    public let key: StorageKey
    public let byteSize: Int
    public let contents: Data?
    public let versionTag: StorageVersionTag
    public let modifiedAt: Date

    public init(
        name: String,
        key: StorageKey,
        byteSize: Int,
        contents: Data?,
        versionTag: StorageVersionTag,
        modifiedAt: Date
    ) {
        self.name = name
        self.key = key
        self.byteSize = byteSize
        self.contents = contents
        self.versionTag = versionTag
        self.modifiedAt = modifiedAt
    }
}

public struct CloudLogEntry: Sendable, Hashable {
    public let name: String
    public let key: StorageKey
    public let kind: StorageChangeKind

    public init(name: String, key: StorageKey, kind: StorageChangeKind) {
        self.name = name
        self.key = key
        self.kind = kind
    }
}

public struct CloudLogPage: Sendable, Hashable {
    public let entries: [CloudLogEntry]
    public let token: Data
    public let hasMore: Bool

    public init(entries: [CloudLogEntry], token: Data, hasMore: Bool) {
        self.entries = entries
        self.token = token
        self.hasMore = hasMore
    }
}

public protocol CloudRecordDatabase: Sendable {
    func snapshot(named name: String) async throws(CloudDatabaseFailure) -> CloudRecordSnapshot?

    func objectSnapshots() async throws(CloudDatabaseFailure) -> [CloudRecordSnapshot]

    @discardableResult
    func save(
        _ draft: CloudRecordDraft,
        precondition: StorageWritePrecondition,
        recording entry: CloudLogEntry
    ) async throws(CloudDatabaseFailure) -> CloudRecordSnapshot

    func remove(
        recordNamed name: String,
        recording entry: CloudLogEntry
    ) async throws(CloudDatabaseFailure)

    func logEntries(after token: Data?) async throws(CloudDatabaseFailure) -> CloudLogPage
}
