import AnchorDomain
import Foundation

public struct StorageObject: Sendable, Hashable {
    public let key: StorageKey
    public let contents: Data

    public init(key: StorageKey, contents: Data) {
        self.key = key
        self.contents = contents
    }
}
