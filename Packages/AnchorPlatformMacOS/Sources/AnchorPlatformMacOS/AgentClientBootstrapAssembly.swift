import AnchorApplication
import Foundation

public enum AgentClientBootstrapAssembly {
    public static func makeCoordinator(supportDirectoryURL: URL) -> AgentClientBootstrapCoordinator
    {
        let environment = ProcessInfo.processInfo.environment
        return makeCoordinator(
            supportDirectoryURL: supportDirectoryURL,
            homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
            environment: environment,
            knownDirectoryURLs: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].map {
                URL(filePath: $0, directoryHint: .isDirectory)
            },
            runner: FoundationAgentCommandRunner(inheritedEnvironment: environment))
    }

    static func makeCoordinator(
        supportDirectoryURL: URL, homeDirectoryURL: URL, environment: [String: String],
        knownDirectoryURLs: [URL], runner: any AgentCommandRunning
    ) -> AgentClientBootstrapCoordinator {
        let locator = MacOSAgentExecutableLocator(
            environment: environment, knownDirectoryURLs: knownDirectoryURLs, runner: runner)
        let bootstrapURL = supportDirectoryURL.appending(path: "agent-bootstrap")
        let receipts = AgentBootstrapReceiptStore(
            directoryURL: bootstrapURL.appending(path: "receipts"))
        let recovery = AgentConfigurationRecoveryStore(
            directoryURL: bootstrapURL.appending(path: "recovery"))
        let claudeDirectory = environment["CLAUDE_CONFIG_DIR"].map { URL(filePath: $0) }
        let codexDirectory = environment["CODEX_HOME"].map { URL(filePath: $0) }
        let claudeConfigurationURL = (claudeDirectory ?? homeDirectoryURL).appending(
            path: ".claude.json")
        let codexConfigurationURL = (codexDirectory ?? homeDirectoryURL.appending(path: ".codex"))
            .appending(path: "config.toml")

        return AgentClientBootstrapCoordinator { workspaceURL in
            BootstrapInstalledAgentClientsAction(configurers: [
                ClaudeCodeMCPBootstrapDriver(
                    locator: locator, runner: runner, configurationURL: claudeConfigurationURL,
                    workingDirectoryURL: workspaceURL, receipts: receipts, recovery: recovery,
                    configurationDirectoryURL: claudeDirectory,
                    defaultHomeDirectoryURL: homeDirectoryURL),
                CodexMCPBootstrapDriver(
                    locator: locator, runner: runner, configurationURL: codexConfigurationURL,
                    receipts: receipts, recovery: recovery,
                    configurationDirectoryURL: codexDirectory,
                    defaultHomeDirectoryURL: homeDirectoryURL),
            ])
        }
    }
}
