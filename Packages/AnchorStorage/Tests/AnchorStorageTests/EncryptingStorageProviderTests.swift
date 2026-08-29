import AnchorDomain
import AnchorStorageTestSupport
import CryptoKit
import Foundation
import Testing

@testable import AnchorStorage

@Suite("Encrypting storage provider")
struct EncryptingStorageProviderTests {
    private let key = SymmetricKey(size: .bits256)

    private func makeKey(from seed: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(seed.utf8)))
    }

    @Test("it honours the storage provider contract")
    func itHonoursTheStorageProviderContract() async throws {
        try await verifyStorageProviderConformance {
            EncryptingStorageProvider(
                wrapping: InMemoryStorageProvider(), key: SymmetricKey(size: .bits256))
        }
    }

    @Test("what reaches the storage underneath is not the text that was written")
    func whatReachesTheStorageUnderneathIsNotTheTextThatWasWritten() async throws {
        let underneath = InMemoryStorageProvider()
        let storageKey = try #require(StorageKey(rawValue: "sessions/claude/one.json"))

        try await EncryptingStorageProvider(wrapping: underneath, key: key)
            .putObject(
                StorageObject(key: storageKey, contents: Data("the database password".utf8)),
                precondition: .none
            )

        let stored = try #require(try await underneath.object(for: storageKey))

        #expect(
            String(decoding: stored.object.contents, as: UTF8.self)
                .contains("the database password") == false)
    }

    @Test("another provider with the same key reads what this one wrote")
    func anotherProviderWithTheSameKeyReadsWhatThisOneWrote() async throws {
        let underneath = InMemoryStorageProvider()
        let storageKey = try #require(StorageKey(rawValue: "sessions/claude/one.json"))
        let sharedKey = makeKey(from: "the shared key")

        try await EncryptingStorageProvider(wrapping: underneath, key: sharedKey)
            .putObject(
                StorageObject(key: storageKey, contents: Data("remembered".utf8)),
                precondition: .none
            )

        let read = try await EncryptingStorageProvider(wrapping: underneath, key: sharedKey)
            .object(for: storageKey)

        #expect(read?.object.contents == Data("remembered".utf8))
    }

    @Test("a different key does not read it")
    func aDifferentKeyDoesNotReadIt() async throws {
        let underneath = InMemoryStorageProvider()
        let storageKey = try #require(StorageKey(rawValue: "sessions/claude/one.json"))

        try await EncryptingStorageProvider(wrapping: underneath, key: makeKey(from: "mine"))
            .putObject(
                StorageObject(key: storageKey, contents: Data("secret".utf8)), precondition: .none
            )

        await #expect(throws: StorageFailure.contentUnreadable(storageKey)) {
            try await EncryptingStorageProvider(
                wrapping: underneath, key: self.makeKey(from: "theirs")
            ).object(for: storageKey)
        }
    }

    @Test("content altered underneath is refused instead of returned")
    func contentAlteredUnderneathIsRefusedInsteadOfReturned() async throws {
        let underneath = InMemoryStorageProvider()
        let storageKey = try #require(StorageKey(rawValue: "sessions/claude/one.json"))
        let provider = EncryptingStorageProvider(wrapping: underneath, key: key)

        try await provider.putObject(
            StorageObject(key: storageKey, contents: Data("trustworthy".utf8)),
            precondition: .none
        )
        let sealed = try #require(try await underneath.object(for: storageKey)).object.contents
        var tampered = sealed
        tampered[tampered.count - 1] ^= 0xFF
        try await underneath.putObject(
            StorageObject(key: storageKey, contents: tampered), precondition: .none
        )

        await #expect(throws: StorageFailure.contentUnreadable(storageKey)) {
            try await provider.object(for: storageKey)
        }
    }

    @Test("a key that was never written is absent rather than unreadable")
    func aKeyThatWasNeverWrittenIsAbsentRatherThanUnreadable() async throws {
        let provider = EncryptingStorageProvider(wrapping: InMemoryStorageProvider(), key: key)

        #expect(
            try await provider.object(for: try #require(StorageKey(rawValue: "nothing"))) == nil)
    }
}
