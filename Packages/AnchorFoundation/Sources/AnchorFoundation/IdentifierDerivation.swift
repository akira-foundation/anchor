import CryptoKit
import Foundation

extension Identifier {
    public static func derived(fromSeed seed: String) -> Identifier<Subject> {
        let digest = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        let hexadecimal = digest.map { String(format: "%02x", $0) }.joined()
        let grouped = [
            hexadecimal.prefix(8),
            hexadecimal.dropFirst(8).prefix(4),
            hexadecimal.dropFirst(12).prefix(4),
            hexadecimal.dropFirst(16).prefix(4),
            hexadecimal.dropFirst(20).prefix(12),
        ]

        guard let identifier = Identifier<Subject>(rawValue: grouped.joined(separator: "-")) else {
            return Identifier<Subject>()
        }

        return identifier
    }
}
