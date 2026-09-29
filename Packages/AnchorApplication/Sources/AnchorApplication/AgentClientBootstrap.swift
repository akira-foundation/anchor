import Foundation

public enum AgentClient: String, Sendable, Codable, CaseIterable {
    case claudeCode
    case codex
}

public struct AgentMCPDefinition: Sendable, Codable, Equatable {
    public let command: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(command: String, arguments: [String], environment: [String: String]) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }
}

public struct AgentMCPRegistration: Sendable, Equatable {
    public let serverName: String
    public let helperExecutableURL: URL
    public let workspaceURL: URL
    public let definition: AgentMCPDefinition

    public init?(serverName: String, helperExecutableURL: URL, workspaceURL: URL) {
        guard serverName == "anchor",
            helperExecutableURL.isFileURL,
            helperExecutableURL.path.hasPrefix("/"),
            workspaceURL.isFileURL,
            workspaceURL.path.hasPrefix("/")
        else { return nil }

        let standardizedHelperURL = helperExecutableURL.standardizedFileURL
        let standardizedWorkspaceURL = workspaceURL.standardizedFileURL
        self.serverName = serverName
        self.helperExecutableURL = standardizedHelperURL
        self.workspaceURL = standardizedWorkspaceURL
        self.definition = AgentMCPDefinition(
            command: standardizedHelperURL.path,
            arguments: ["--workspace", standardizedWorkspaceURL.path],
            environment: [:]
        )
    }
}

public enum AgentClientBootstrapFailureStage: String, Sendable, Codable, Equatable {
    case discovery
    case inspection
    case backup
    case removal
    case addition
    case verification
    case restoration
}

public enum AgentClientBootstrapOutcome: Sendable, Equatable {
    case alreadyConfigured
    case configured
    case updated
    case notInstalled
    case conflict
    case failed(AgentClientBootstrapFailureStage)
    case recoveryRequired

    public var requiresRestart: Bool {
        switch self {
        case .configured, .updated:
            true
        case .alreadyConfigured, .notInstalled, .conflict, .failed, .recoveryRequired:
            false
        }
    }
}

public struct AgentClientBootstrapEntry: Sendable, Equatable {
    public let client: AgentClient
    public let outcome: AgentClientBootstrapOutcome

    public init(client: AgentClient, outcome: AgentClientBootstrapOutcome) {
        self.client = client
        self.outcome = outcome
    }
}

public struct AgentClientBootstrapReport: Sendable, Equatable {
    public let entries: [AgentClientBootstrapEntry]

    init(entries: [AgentClientBootstrapEntry]) {
        self.entries = entries
    }
}

public protocol AgentClientMCPConfiguring: Sendable {
    var client: AgentClient { get }

    func ensureUserRegistration(
        _ registration: AgentMCPRegistration
    ) async -> AgentClientBootstrapOutcome
}
