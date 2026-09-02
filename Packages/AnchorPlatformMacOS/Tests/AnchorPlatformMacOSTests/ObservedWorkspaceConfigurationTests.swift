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

    private func makeWorkspace(named name: String) throws -> String {
        let workspace = FileManager.default.temporaryDirectory
            .appending(path: "anchor-observed/\(UUID().uuidString)/\(name)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        return workspace.path(percentEncoded: false)
    }

    @Test("a machine that was never told anything watches nothing, and does not fail")
    func machineThatWasNeverToldAnythingWatchesNothingAndDoesNotFail() throws {
        let configuration = ObservedWorkspaceConfiguration(fileURL: temporaryFileURL())

        #expect(try configuration.observedWorkspace() == nil)
    }

    @Test("the workspace and the project name survive the round trip")
    func workspaceAndProjectNameSurviveRoundTrip() throws {
        let workspacePath = try makeWorkspace(named: "anchor-fixture")
        let fileURL = try writing(
            #"{"workspacePath": "\#(workspacePath)", "projectName": "anchor"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let observed = try #require(
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace())

        #expect(observed.projectName == "anchor")
        #expect(observed.workspaceURL.path(percentEncoded: false) == workspacePath)
    }

    @Test("the path is spelled the way the rest of the system spells it")
    func pathIsSpelledTheWayRestOfSystemSpellsIt() throws {
        let workspacePath = try makeWorkspace(named: "anchor-fixture")
        let fileURL = try writing(
            #"{"workspacePath": "\#(workspacePath)/", "projectName": "anchor"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let observed = try #require(
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace())

        #expect(observed.workspaceURL.path(percentEncoded: false) == workspacePath)
        #expect(!observed.workspaceURL.path(percentEncoded: false).hasSuffix("/"))
    }

    @Test("two machines watching the same project agree on which project it is")
    func twoMachinesWatchingSameProjectAgreeOnWhichProjectItIs() throws {
        let onOneMachine = try writing(
            #"{"workspacePath": "\#(try makeWorkspace(named: "one/anchor"))", "projectName": "anchor"}"#
        )
        let onAnother = try writing(
            #"{"workspacePath": "\#(try makeWorkspace(named: "another/anchor"))", "projectName": "anchor"}"#
        )
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
        let shared = try makeWorkspace(named: "shared")
        let anchor = try writing(#"{"workspacePath": "\#(shared)", "projectName": "anchor"}"#)
        let other = try writing(#"{"workspacePath": "\#(shared)", "projectName": "dotsync"}"#)
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
        let fileURL = try writing(
            #"{"workspacePath": "\#(try makeWorkspace(named: "anchor-fixture"))"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: ObservedWorkspaceConfiguration.Failure.self) {
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace()
        }
    }

    @Test("a project name that is only whitespace names no project")
    func projectNameThatIsOnlyWhitespaceNamesNoProject() throws {
        let fileURL = try writing(
            #"{"workspacePath": "\#(try makeWorkspace(named: "anchor-fixture"))", "projectName": "   "}"#
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: ObservedWorkspaceConfiguration.Failure.self) {
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace()
        }
    }
}

@Suite("A workspace this machine was told to watch but cannot")
struct AbsentObservedWorkspaceTests {
    private func writing(_ contents: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "anchor-workspace-\(UUID().uuidString).json")
        try Data(contents.utf8).write(to: fileURL)

        return fileURL
    }

    @Test("a workspace that is not there is not watched in silence")
    func workspaceThatIsNotThereIsNotWatchedInSilence() throws {
        let fileURL = try writing(
            #"{"workspacePath": "/tmp/anchor-nowhere-XXXX", "projectName": "anchor"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: ObservedWorkspaceConfiguration.Failure.self) {
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace()
        }
    }

    @Test("a workspace that is a file rather than a folder is not watched in silence")
    func workspaceThatIsFileRatherThanFolderIsNotWatchedInSilence() throws {
        let file = try writing("not a workspace")
        let fileURL = try writing(
            #"{"workspacePath": "\#(file.path(percentEncoded: false))", "projectName": "anchor"}"#)
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: fileURL)
        }

        #expect(throws: ObservedWorkspaceConfiguration.Failure.self) {
            try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace()
        }
    }

    @Test("a workspace that is really there is watched")
    func workspaceThatIsReallyThereIsWatched() throws {
        let workspace = try WorkspaceFixture.make(["docs/superpowers/plans/00.md": "plan"])
        let fileURL = try writing(
            #"{"workspacePath": "\#(workspace.path(percentEncoded: false))", "projectName": "anchor"}"#
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(try ObservedWorkspaceConfiguration(fileURL: fileURL).observedWorkspace() != nil)
    }
}
