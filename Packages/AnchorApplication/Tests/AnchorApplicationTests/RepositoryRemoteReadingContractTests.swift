import AnchorDomain
import Foundation
import Testing

@testable import AnchorApplication

@Suite("Repository remote reading contract")
struct RepositoryRemoteReadingContractTests {
    @Test("a repository with one remote reports its canonical form")
    func aRepositoryWithOneRemoteReportsItsCanonicalForm() async throws {
        let reader = FixtureRepositoryRemoteReader(
            outcomesByDirectory: [
                URL(filePath: "/Developer/payable"):
                    .remote(
                        try #require(
                            CanonicalRepositoryRemote(
                                gitRemote: "git@github.com:akira-io/payable.git")))
            ]
        )

        let outcome = try await reader.readRepositoryRemote(
            atDirectory: URL(filePath: "/Developer/payable"))

        #expect(
            outcome
                == .remote(
                    try #require(CanonicalRepositoryRemote(rawValue: "github.com/akira-io/payable"))
                ))
    }

    @Test("a repository without a remote is reported, not refused")
    func aRepositoryWithoutARemoteIsReportedNotRefused() async throws {
        let reader = FixtureRepositoryRemoteReader(
            outcomesByDirectory: [URL(filePath: "/Developer/scratch"): .repositoryWithoutRemote]
        )

        let outcome = try await reader.readRepositoryRemote(
            atDirectory: URL(filePath: "/Developer/scratch"))

        #expect(outcome == .repositoryWithoutRemote)
    }

    @Test("a directory that is not a repository is reported, not thrown")
    func aDirectoryThatIsNotARepositoryIsReportedNotThrown() async throws {
        let reader = FixtureRepositoryRemoteReader(outcomesByDirectory: [:])

        let outcome = try await reader.readRepositoryRemote(
            atDirectory: URL(filePath: "/Downloads"))

        #expect(outcome == .notARepository)
    }

    @Test("several remote names are reported for the user to choose")
    func severalRemoteNamesAreReportedForTheUserToChoose() async throws {
        let remoteNames = ["origin", "upstream"]
        let reader = FixtureRepositoryRemoteReader(
            outcomesByDirectory: [
                URL(filePath: "/Developer/fork"): .severalRemoteNames(remoteNames)
            ]
        )

        let outcome = try await reader.readRepositoryRemote(
            atDirectory: URL(filePath: "/Developer/fork"))

        #expect(outcome == .severalRemoteNames(remoteNames))
    }

    @Test("a reader that cannot run reports a failure rather than a missing repository")
    func aReaderThatCannotRunReportsAFailure() async {
        let reader = FixtureRepositoryRemoteReader(
            outcomesByDirectory: [:], failsWith: .gitUnavailable)

        await #expect(throws: RepositoryRemoteFailure.gitUnavailable) {
            try await reader.readRepositoryRemote(atDirectory: URL(filePath: "/Developer/payable"))
        }
    }
}

private struct FixtureRepositoryRemoteReader: RepositoryRemoteReading {
    let outcomesByDirectory: [URL: RepositoryRemoteOutcome]
    var failsWith: RepositoryRemoteFailure?

    func readRepositoryRemote(atDirectory directoryURL: URL) async throws -> RepositoryRemoteOutcome
    {
        if let failsWith { throw failsWith }

        return outcomesByDirectory[directoryURL] ?? .notARepository
    }
}
