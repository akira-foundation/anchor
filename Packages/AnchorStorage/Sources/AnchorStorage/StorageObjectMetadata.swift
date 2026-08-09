import AnchorDomain
import Foundation

public struct StorageObjectMetadata: Sendable, Hashable, Codable {
    public let key: StorageKey
    public let byteSize: Int
    public let modifiedAt: Date
    public let versionTag: StorageVersionTag

    public init(key: StorageKey, byteSize: Int, modifiedAt: Date, versionTag: StorageVersionTag) {
        self.key = key
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.versionTag = versionTag
    }
}
