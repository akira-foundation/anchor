import CryptoKit
import Foundation
import Security

public struct SynchronizedEncryptionKeyStore: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case keychainRefused(OSStatus)
    }

    public static let defaultService = "io.akira.anchor"
    public static let defaultAccount = "context-encryption-key"

    private let service: String
    private let account: String

    public init(
        service: String = SynchronizedEncryptionKeyStore.defaultService,
        account: String = SynchronizedEncryptionKeyStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    public static func itemAttributes(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
    }

    public func existingKey() throws(Failure) -> SymmetricKey? {
        var query = Self.itemAttributes(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw .keychainRefused(status)
        }

        return SymmetricKey(data: data)
    }

    public func keyCreatingIfNeeded() throws(Failure) -> SymmetricKey {
        if let existing = try existingKey() { return existing }

        let created = SymmetricKey(size: .bits256)
        var item = Self.itemAttributes(service: service, account: account)
        item[kSecValueData as String] = created.withUnsafeBytes { Data($0) }

        let status = SecItemAdd(item as CFDictionary, nil)

        guard status == errSecSuccess else {
            guard status == errSecDuplicateItem, let existing = try existingKey() else {
                throw .keychainRefused(status)
            }

            return existing
        }

        return created
    }

    public func removeKey() throws(Failure) {
        let status = SecItemDelete(
            Self.itemAttributes(service: service, account: account) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .keychainRefused(status)
        }
    }
}
