import AnchorApplication
import AnchorDomain
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Git command repository remote reader")
struct GitCommandRepositoryRemoteReaderTests {
    private let reader = GitCommandRepositoryRemoteReader()

    @Test("a repository with one remote reports its canonical form")
    func aRepositoryWithOneRemoteReportsItsCanonicalForm() async throws {
        let repository = try GitFixture.makeRepository(named: "payable")
        try GitFixture.addRemote(
            named: "origin", url: "git@github.com:akira-io/payable.git", to: repository)

        let outcome = try await reader.readRepositoryRemote(atDirectory: repository)

        #expect(
            outcome
                == .remote(
                    try #require(CanonicalRepositoryRemote(rawValue: "github.com/akira-io/payable"))
                ))
    }

    @Test("a worktree reports the remote of the repository it belongs to")
    func aWorktreeReportsTheRemoteOfTheRepositoryItBelongsTo() async throws {
        let repository = try GitFixture.makeRepository(named: "worktree-parent")
        try GitFixture.addRemote(
            named: "origin", url: "https://github.com/akira-io/parent.git", to: repository)
        let worktree = try GitFixture.addWorktree(named: "checkout", to: repository)

        let outcome = try await reader.readRepositoryRemote(atDirectory: worktree)

        #expect(
            outcome
                == .remote(
                    try #require(CanonicalRepositoryRemote(rawValue: "github.com/akira-io/parent")))
        )
    }

    @Test("a remote reached through an included config file is found")
    func aRemoteReachedThroughAnIncludedConfigFileIsFound() async throws {
        let repository = try GitFixture.makeRepository(named: "included")
        try GitFixture.addIncludedRemote(
            url: "https://github.com/akira-io/from-include.git", to: repository)

        let outcome = try await reader.readRepositoryRemote(atDirectory: repository)

        #expect(
            outcome
                == .remote(
                    try #require(
                        CanonicalRepositoryRemote(rawValue: "github.com/akira-io/from-include")))
        )
    }

    @Test("a repository without a remote is reported as such")
    func aRepositoryWithoutARemoteIsReportedAsSuch() async throws {
        let repository = try GitFixture.makeRepository(named: "scratch")

        let outcome = try await reader.readRepositoryRemote(atDirectory: repository)

        #expect(outcome == .repositoryWithoutRemote)
    }

    @Test("a directory that is not a repository is reported as such")
    func aDirectoryThatIsNotARepositoryIsReportedAsSuch() async throws {
        let plainDirectory = try GitFixture.makePlainDirectory(named: "downloads")

        let outcome = try await reader.readRepositoryRemote(atDirectory: plainDirectory)

        #expect(outcome == .notARepository)
    }

    @Test("origin wins when a fork also carries an upstream")
    func originWinsWhenAForkAlsoCarriesAnUpstream() async throws {
        let repository = try GitFixture.makeRepository(named: "fork")
        try GitFixture.addRemote(
            named: "origin", url: "https://github.com/kid/fork.git", to: repository)
        try GitFixture.addRemote(
            named: "upstream", url: "https://github.com/akira-io/original.git", to: repository)

        let outcome = try await reader.readRepositoryRemote(atDirectory: repository)

        #expect(
            outcome
                == .remote(try #require(CanonicalRepositoryRemote(rawValue: "github.com/kid/fork")))
        )
    }

    @Test("a single remote is used even when it is not called origin")
    func aSingleRemoteIsUsedEvenWhenItIsNotCalledOrigin() async throws {
        let repository = try GitFixture.makeRepository(named: "single")
        try GitFixture.addRemote(
            named: "gitlab", url: "https://gitlab.example.com/team/service.git", to: repository)

        let outcome = try await reader.readRepositoryRemote(atDirectory: repository)

        #expect(
            outcome
                == .remote(
                    try #require(
                        CanonicalRepositoryRemote(rawValue: "gitlab.example.com/team/service")))
        )
    }

    @Test("several remote names are handed back to be chosen")
    func severalRemoteNamesAreHandedBack() async throws {
        let repository = try GitFixture.makeRepository(named: "ambiguous")
        try GitFixture.addRemote(
            named: "gitlab", url: "https://gitlab.example.com/team/service.git", to: repository)
        try GitFixture.addRemote(
            named: "mirror", url: "https://github.com/team/service.git", to: repository)

        let outcome = try await reader.readRepositoryRemote(atDirectory: repository)

        #expect(outcome == .severalRemoteNames(["gitlab", "mirror"]))
    }
}
