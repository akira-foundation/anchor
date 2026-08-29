import CryptoKit
import Foundation
import Security
import Testing

@testable import AnchorPlatformMacOS

private let liveKeychainIsAllowed =
    ProcessInfo.processInfo.environment["ANCHOR_KEYCHAIN_TESTS"]
    != nil

@Suite("The key that travels with the account")
struct SynchronizedEncryptionKeyStoreTests {
    @Test("the item is marked to travel with the iCloud keychain")
    func theItemIsMarkedToTravelWithTheICloudKeychain() {
        let attributes = SynchronizedEncryptionKeyStore.itemAttributes(
            service: "io.akira.anchor.test", account: "key")

        #expect(attributes[kSecAttrSynchronizable as String] as? Bool == true)
    }

    @Test("the item is readable after the first unlock rather than only while unlocked")
    func theItemIsReadableAfterTheFirstUnlockRatherThanOnlyWhileUnlocked() {
        let attributes = SynchronizedEncryptionKeyStore.itemAttributes(
            service: "io.akira.anchor.test", account: "key")
        let accessible = attributes[kSecAttrAccessible as String] as! CFString

        #expect(accessible == kSecAttrAccessibleAfterFirstUnlock)
    }

    @Test("the item is a generic password under the service and account it was given")
    func theItemIsAGenericPasswordUnderTheServiceAndAccountItWasGiven() {
        let attributes = SynchronizedEncryptionKeyStore.itemAttributes(
            service: "io.akira.anchor.test", account: "key")

        #expect(attributes[kSecAttrService as String] as? String == "io.akira.anchor.test")
        #expect(attributes[kSecAttrAccount as String] as? String == "key")
        #expect((attributes[kSecClass as String] as! CFString) == kSecClassGenericPassword)
    }

    @Test("the default account is not shared with another Akira product")
    func theDefaultAccountIsNotSharedWithAnotherAkiraProduct() {
        #expect(SynchronizedEncryptionKeyStore.defaultService == "io.akira.anchor")
        #expect(SynchronizedEncryptionKeyStore.defaultAccount == "context-encryption-key")
    }
}

@Suite(
    "The key that travels with the account, against the real keychain",
    .enabled(if: liveKeychainIsAllowed)
)
struct SynchronizedEncryptionKeyStoreLiveTests {
    @Test("a key created once is the same key the next time it is asked for")
    func aKeyCreatedOnceIsTheSameKeyTheNextTimeItIsAskedFor() throws {
        let store = SynchronizedEncryptionKeyStore(
            service: "io.akira.anchor.test", account: "key-\(UUID().uuidString)")

        defer { try? store.removeKey() }

        let created = try store.keyCreatingIfNeeded()
        let read = try store.keyCreatingIfNeeded()

        #expect(created == read)
    }

    @Test("a key that was never created is absent")
    func aKeyThatWasNeverCreatedIsAbsent() throws {
        let store = SynchronizedEncryptionKeyStore(
            service: "io.akira.anchor.test", account: "absent-\(UUID().uuidString)")

        #expect(try store.existingKey() == nil)
    }
}
