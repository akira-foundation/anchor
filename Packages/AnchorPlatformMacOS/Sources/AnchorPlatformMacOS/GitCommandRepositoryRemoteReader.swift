import AnchorApplication
import AnchorDomain
import Foundation

public struct GitCommandRepositoryRemoteReader: RepositoryRemoteReading {
    private let commandLauncherURL: URL

    public init(commandLauncherURL: URL = URL(filePath: "/usr/bin/env")) {
        self.commandLauncherURL = commandLauncherURL
    }

    public func readRepositoryRemote(
        atDirectory directoryURL: URL
    ) async throws -> RepositoryRemoteOutcome {
        guard try runGit(["rev-parse", "--git-dir"], inDirectory: directoryURL) != nil else {
            return .notARepository
        }

        let remoteNames = try remoteNames(inDirectory: directoryURL)
        guard let chosenRemoteName = chooseRemoteName(from: remoteNames) else {
            return remoteNames.isEmpty ? .repositoryWithoutRemote : .severalRemoteNames(remoteNames)
        }

        let remoteURL = try runGit(
            ["config", "--get", "remote.\(chosenRemoteName).url"],
            inDirectory: directoryURL
        )
        guard let remoteURL, let repositoryRemote = CanonicalRepositoryRemote(gitRemote: remoteURL)
        else {
            return .repositoryWithoutRemote
        }

        return .remote(repositoryRemote)
    }

    private func remoteNames(inDirectory directoryURL: URL) throws -> [String] {
        let listing = try runGit(["remote"], inDirectory: directoryURL) ?? ""

        return listing.split(separator: "\n").map(String.init)
    }

    private func chooseRemoteName(from remoteNames: [String]) -> String? {
        guard !remoteNames.contains("origin") else { return "origin" }

        return remoteNames.count == 1 ? remoteNames.first : nil
    }

    private func runGit(_ arguments: [String], inDirectory directoryURL: URL) throws -> String? {
        let process = Process()
        process.executableURL = commandLauncherURL
        process.arguments = ["git", "-C", directoryURL.path()] + arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw RepositoryRemoteFailure.gitUnavailable
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
