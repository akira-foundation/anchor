import AnchorDomain
import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("The workspace this machine was told to watch")
struct ObservedWorkspaceConfigurationTests {
    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "anchor-workspace-\(UUID().uuidString).json")
    }

    private func writing(_ contents: String) throws -> URL {
        let fileURL = temporaryFileURL()
        try Data(contents.utf8).write(to: fileURL)

        return fileURL
    }

    @Test("a machine that was never told anything watches nothing, and does not fail")
    func machineThatWasNeverToldAnythingWatchesNothingAndDoesNotFail() throws {
        let configuration = ObservedWorkspaceConfiguration(fileURL: temporaryFileURL())

        #expect(try configuration.observedWorkspace() == nil)
    }

    @Test("the workspace and the project name survive the round trip")
    func workspaceAndProjectNameSurviveRoundTrip() throws {
        let fileURL = try writing(
            #"{"workspacePath": "/tmp/anchor-fixture", "projectName": "anchor"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let observed = try #require(
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace())

        #expect(observed.projectName == "anchor")
        #expect(observed.workspaceURL.path(percentEncoded: false).hasSuffix("anchor-fixture"))
    }

    @Test("the path is spelled the way the rest of the system spells it")
    func pathIsSpelledTheWayRestOfSystemSpellsIt() throws {
        let fileURL = try writing(
            #"{"workspacePath": "/tmp/anchor-fixture/", "projectName": "anchor"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let observed = try #require(
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace())

        #expect(
            WorkspacePath.comparable(observed.workspaceURL)
                == WorkspacePath.comparable(URL(filePath: "/tmp/anchor-fixture")))
    }

    @Test("two machines watching the same project agree on which project it is")
    func twoMachinesWatchingSameProjectAgreeOnWhichProjectItIs() throws {
        let onOneMachine = try writing(
            #"{"workspacePath": "/Users/one/code/anchor", "projectName": "anchor"}"#)
        let onAnother = try writing(
            #"{"workspacePath": "/Users/another/work/anchor", "projectName": "anchor"}"#)
        defer {
            try? FileManager.default.removeItem(at: onOneMachine)
            try? FileManager.default.removeItem(at: onAnother)
        }

        let first = try #require(
            try ObservedWorkspaceConfiguration(fileURL: onOneMachine).observedWorkspace())
        let second = try #require(
            try ObservedWorkspaceConfiguration(fileURL: onAnother).observedWorkspace())

        #expect(first.projectID == second.projectID)
        #expect(first.workspaceURL != second.workspaceURL)
    }

    @Test("two different projects are not the same project")
    func twoDifferentProjectsAreNotSameProject() throws {
        let anchor = try writing(#"{"workspacePath": "/tmp/a", "projectName": "anchor"}"#)
        let other = try writing(#"{"workspacePath": "/tmp/a", "projectName": "dotsync"}"#)
        defer {
            try? FileManager.default.removeItem(at: anchor)
            try? FileManager.default.removeItem(at: other)
        }

        let first = try #require(
            try ObservedWorkspaceConfiguration(fileURL: anchor).observedWorkspace())
        let second = try #require(
            try ObservedWorkspaceConfiguration(fileURL: other).observedWorkspace())

        #expect(first.projectID != second.projectID)
    }

    @Test("a configuration that exists and cannot be read is not silently ignored")
    func configurationThatExistsAndCannotBeReadIsNotSilentlyIgnored() throws {
        let fileURL = try writing("not json at all")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: ObservedWorkspaceConfiguration.Failure.self) {
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace()
        }
    }

    @Test("a configuration missing the project name is not read as an unnamed project")
    func configurationMissingProjectNameIsNotReadAsUnnamedProject() throws {
        let fileURL = try writing(#"{"workspacePath": "/tmp/anchor-fixture"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: ObservedWorkspaceConfiguration.Failure.self) {
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace()
        }
    }

    @Test("a project name that is only whitespace names no project")
    func projectNameThatIsOnlyWhitespaceNamesNoProject() throws {
        let fileURL = try writing(
            #"{"workspacePath": "/tmp/anchor-fixture", "projectName": "   "}"#)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: ObservedWorkspaceConfiguration.Failure.self) {
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace()
        }
    }
}
