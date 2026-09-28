import AnchorApplication
import Foundation

protocol AgentExecutableLocating: Sendable {
    func locate(_ client: AgentClient) async -> URL?
}

enum AgentExecutableFileValidation {
    static func isExecutableRegularFile(at executableURL: URL) -> Bool {
        let resolvedExecutableURL = executableURL.resolvingSymlinksInPath().standardizedFileURL
        guard
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: resolvedExecutableURL.path),
            attributes[.type] as? FileAttributeType == .typeRegular
        else { return false }

        return FileManager.default.isExecutableFile(atPath: resolvedExecutableURL.path)
    }
}

struct MacOSAgentExecutableLocator: AgentExecutableLocating {
    private let environment: [String: String]
    private let knownDirectoryURLs: [URL]
    private let runner: any AgentCommandRunning
    private let discoveryMaximumRunDuration: TimeInterval

    init(
        environment: [String: String],
        knownDirectoryURLs: [URL],
        runner: any AgentCommandRunning,
        discoveryMaximumRunDuration: TimeInterval = 5
    ) {
        self.environment = environment
        self.knownDirectoryURLs = knownDirectoryURLs
        self.runner = runner
        self.discoveryMaximumRunDuration = discoveryMaximumRunDuration
    }

    func locate(_ client: AgentClient) async -> URL? {
        let executableName =
            switch client {
            case .claudeCode: "claude"
            case .codex: "codex"
            }
        var visitedPaths = Set<String>()

        for directoryURL in searchDirectoryURLs() {
            let candidateURL = directoryURL.appending(path: executableName)
                .standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
            guard visitedPaths.insert(candidateURL.path).inserted,
                AgentExecutableFileValidation.isExecutableRegularFile(at: candidateURL)
            else { continue }

            let command = AgentCommand(
                executableURL: candidateURL,
                arguments: ["--version"],
                environment: environment,
                maximumRunDuration: discoveryMaximumRunDuration)
            guard let commandOutput = try? await runner.run(command),
                commandOutput.terminationStatus == 0,
                identifies(client, output: commandOutput.standardOutput)
            else { continue }

            return candidateURL
        }

        return nil
    }

    private func searchDirectoryURLs() -> [URL] {
        let inheritedDirectories = (environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { URL(filePath: String($0), directoryHint: .isDirectory) }
        let homeDirectoryURL =
            environment["HOME"].map {
                URL(filePath: $0, directoryHint: .isDirectory)
            } ?? FileManager.default.homeDirectoryForCurrentUser
        return inheritedDirectories
            + [homeDirectoryURL.appending(path: ".local/bin", directoryHint: .isDirectory)]
            + knownDirectoryURLs
    }

    private func identifies(_ client: AgentClient, output: Data) -> Bool {
        let version = String(decoding: output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch client {
        case .claudeCode:
            if version.hasPrefix("Claude Code ") {
                return isNumericClaudeVersion(String(version.dropFirst("Claude Code ".count)))
            }
            if version.hasSuffix(" (Claude Code)") {
                return isNumericClaudeVersion(String(version.dropLast(" (Claude Code)".count)))
            }
            return isNumericClaudeVersion(version)
        case .codex:
            return version.hasPrefix("codex-cli ") && version.count > "codex-cli ".count
        }
    }

    private func isNumericClaudeVersion(_ version: String) -> Bool {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 3
            && components.allSatisfy {
                !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
            }
    }
}
