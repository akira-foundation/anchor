import Foundation

public enum AgentSessionArtifactNaming {
    public static let rootSegment = "sessions"

    public static func canonicalPrefix(for provider: AgentProvider) -> String {
        "\(rootSegment)/\(provider.rawValue)"
    }

    public static func name(forSession sessionID: SessionID, provider: AgentProvider) -> String {
        "\(canonicalPrefix(for: provider))/\(sessionID.rawValue).json"
    }
}

extension Artifact {
    public var isAgentSessionTranscript: Bool {
        name.hasPrefix(AgentSessionArtifactNaming.canonicalPrefix(for: provider) + "/")
    }
}
