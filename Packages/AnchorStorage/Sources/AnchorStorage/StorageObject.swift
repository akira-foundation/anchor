import AnchorDomain
import Foundation

public struct StorageObject: Sendable, Hashable {
    public let key: StorageKey
    public let contents: Data
    public let expectedVersionTag: StorageVersionTag?

    public init(key: StorageKey, contents: Data, expectedVersionTag: StorageVersionTag? = nil) {
        self.key = key
        self.contents = contents
        self.expectedVersionTag = expectedVersionTag
    }
}
