import Foundation

public enum AgentSessionArtifactNaming {
    public static let rootSegment = "sessions"

    public static func canonicalPrefix(for provider: AgentProvider) -> String {
        "\(rootSegment)/\(provider.rawValue)"
    }

    public static func name(forSession sessionID: SessionID, provider: AgentProvider) -> String {
        "\(canonicalPrefix(for: provider))/\(sessionID.rawValue).json"
    }

    public static func names(_ name: String, aSessionOf provider: AgentProvider) -> Bool {
        name.hasPrefix(canonicalPrefix(for: provider) + "/")
    }
}

extension Artifact {
    public var isAgentSessionTranscript: Bool {
        AgentSessionArtifactNaming.names(name, aSessionOf: provider)
    }
}
