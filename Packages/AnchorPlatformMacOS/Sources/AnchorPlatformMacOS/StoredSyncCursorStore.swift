import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation

public struct StoredSyncCursorStore: SyncCursorStore {
    private static let cursorKey = "sync/remote-cursor"

    private let storage: any StorageProvider

    public init(storage: any StorageProvider) {
        self.storage = storage
    }

    public func cursor() async throws -> String? {
        guard let key = StorageKey(rawValue: Self.cursorKey),
            let stored = try await storage.object(for: key)
        else { return nil }

        return String(decoding: stored.object.contents, as: UTF8.self)
    }

    public func recordCursor(_ cursor: String) async throws {
        guard let key = StorageKey(rawValue: Self.cursorKey) else { return }

        try await storage.putObject(
            StorageObject(key: key, contents: Data(cursor.utf8)), precondition: .none
        )
    }
}
