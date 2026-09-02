import Foundation
import Testing

enum GitFixture {
    static func makePlainDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anchor-git-fixtures/\(UUID().uuidString)/\(name)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
    }

    static func makeRepository(named name: String) throws -> URL {
        let directory = try makePlainDirectory(named: name)
        try runGit([
            "-c", "init.defaultBranch=main", "init", "-q", directory.path(percentEncoded: false),
        ])
        try runGit([
            "-C", directory.path(percentEncoded: false), "config", "user.email",
            "fixture@example.com",
        ])
        try runGit(["-C", directory.path(percentEncoded: false), "config", "user.name", "fixture"])
        try Data("seed\n".utf8).write(to: directory.appending(path: "seed.txt"))
        try runGit(["-C", directory.path(percentEncoded: false), "add", "."])
        try runGit(["-C", directory.path(percentEncoded: false), "commit", "-qm", "chore: seed"])

        return directory
    }

    static func addRemote(named name: String, url: String, to repository: URL) throws {
        try runGit(["-C", repository.path(percentEncoded: false), "remote", "add", name, url])
    }

    static func addWorktree(named name: String, to repository: URL) throws -> URL {
        let worktree = repository.deletingLastPathComponent().appending(path: name)
        try runGit([
            "-C", repository.path(percentEncoded: false), "worktree", "add", "-q",
            worktree.path(percentEncoded: false), "-b", name,
        ])

        return worktree
    }

    static func addIncludedRemote(url: String, to repository: URL) throws {
        let includedConfiguration = repository.deletingLastPathComponent().appending(
            path: "remote.inc")
        let contents = """
            [remote "origin"]
            \turl = \(url)
            \tfetch = +refs/heads/*:refs/remotes/origin/*

            """
        try Data(contents.utf8).write(to: includedConfiguration)
        try runGit([
            "-C", repository.path(percentEncoded: false), "config", "--local", "include.path",
            includedConfiguration.path(percentEncoded: false),
        ])
    }

    private static func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git", "-c", "commit.gpgsign=false"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GitFixtureFailure.commandFailed(arguments, process.terminationStatus)
        }
    }
}

enum GitFixtureFailure: Error {
    case commandFailed([String], Int32)
}
