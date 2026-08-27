import AnchorDomain
import CryptoKit
import Foundation

public enum CloudRecordNaming {
    public static func objectRecordName(for key: StorageKey) -> String {
        let digest = SHA256.hash(data: Data(key.rawValue.utf8))

        return "object-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func logRecordName(recordedAt instant: Date, disambiguator: String) -> String {
        let nanoseconds = Int64((instant.timeIntervalSince1970 * 1_000_000_000).rounded())

        return String(format: "log-%019lld-%@", nanoseconds, disambiguator)
    }
}
