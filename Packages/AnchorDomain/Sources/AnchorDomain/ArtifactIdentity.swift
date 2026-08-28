import AnchorFoundation
import CryptoKit
import Foundation

extension ArtifactID {
    public static func derived(
        projectID: ProjectID, provider: AgentProvider, name: String
    ) -> ArtifactID {
        let seed = "\(projectID.rawValue)/\(provider.rawValue)/\(name)"
        let digest = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        let hexadecimal = digest.map { String(format: "%02x", $0) }.joined()
        let grouped = [
            hexadecimal.prefix(8),
            hexadecimal.dropFirst(8).prefix(4),
            hexadecimal.dropFirst(12).prefix(4),
            hexadecimal.dropFirst(16).prefix(4),
            hexadecimal.dropFirst(20).prefix(12),
        ]

        guard let identifier = ArtifactID(rawValue: grouped.joined(separator: "-")) else {
            return ArtifactID()
        }

        return identifier
    }
}
