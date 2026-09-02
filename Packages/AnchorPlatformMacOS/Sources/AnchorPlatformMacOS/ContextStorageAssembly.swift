import AnchorStorage
import CryptoKit
import Foundation

public enum ContextStorageChoice: Sendable, Hashable {
    case synchronized
    case localOnlyUntilAccountReturns
}

public struct AssembledContextStorage: Sendable {
    public let local: any StorageProvider
    public let remote: (any StorageProvider)?

    public var choice: ContextStorageChoice {
        remote == nil ? .localOnlyUntilAccountReturns : .synchronized
    }
}

public enum ContextStorageAssembly {
    public static func assemble(
        reachingRemote remote: @Sendable () async -> (any StorageProvider)?,
        localRootURL: URL,
        key: SymmetricKey
    ) async -> AssembledContextStorage {
        AssembledContextStorage(
            local: EncryptingStorageProvider(
                wrapping: FileSystemStorageProvider(rootURL: localRootURL), key: key),
            remote: await remote().map { EncryptingStorageProvider(wrapping: $0, key: key) }
        )
    }
}
