import AnchorDomain
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Workspaces whose path a person would type but a URL would encode")
struct AwkwardWorkspacePathTests {
    private let awkwardNames = ["My Projects", "code + notes", "café", "a&b"]

    @Test("the path a workspace is watched under is the one the file system knows")
    func pathWorkspaceIsWatchedUnderIsOneFileSystemKnows() throws {
        for name in awkwardNames {
            let workspaceURL = URL(filePath: "/tmp").appending(path: name)
                .appending(path: "anchor")

            #expect(!FileSystemEventStream.watchedPath(for: workspaceURL).contains("%"))
            #expect(
                FileSystemEventStream.watchedPath(for: workspaceURL)
                    == workspaceURL.path(percentEncoded: false))
        }
    }

    @Test("an event inside an awkwardly named workspace is an event inside it")
    func eventInsideAwkwardlyNamedWorkspaceIsEventInsideIt() throws {
        for name in awkwardNames {
            let workspaceURL = URL(filePath: "/tmp").appending(path: name)
                .appending(path: "anchor")
            let changedPath =
                workspaceURL.path(percentEncoded: false) + "/docs/superpowers/plans/00.md"

            #expect(
                WorkspacePath.relativePath(of: changedPath, under: workspaceURL)
                    == "docs/superpowers/plans/00.md")
        }
    }

    @Test("the Claude folder for an awkwardly named workspace is named after the real path")
    func claudeFolderForAwkwardlyNamedWorkspaceIsNamedAfterRealPath() throws {
        for name in awkwardNames {
            let workspaceURL = URL(filePath: "/tmp").appending(path: name)
                .appending(path: "anchor")

            #expect(
                !ClaudeSessionsLocation.directoryName(forWorkspaceAt: workspaceURL)
                    .contains("%"))
        }
    }

    @Test("a repository under an awkwardly named folder is a repository git can read")
    func repositoryUnderAwkwardlyNamedFolderIsRepositoryGitCanRead() async throws {
        let repository = try GitFixture.makeRepository(named: "My Projects/anchor")
        try GitFixture.addRemote(named: "origin", url: "git@github.com:a/b.git", to: repository)

        let outcome = try await GitCommandRepositoryRemoteReader().readRepositoryRemote(
            atDirectory: repository)

        let expected = try #require(CanonicalRepositoryRemote(rawValue: "github.com/a/b"))

        #expect(outcome == .remote(expected))
    }
}
