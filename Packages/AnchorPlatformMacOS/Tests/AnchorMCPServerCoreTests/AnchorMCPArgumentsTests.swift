import Foundation
import Testing

@testable import AnchorMCPServerCore

struct AnchorMCPArgumentsTests {
    @Test("workspace requires one absolute existing path")
    func workspaceRequiresOneAbsoluteExistingPath() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appending(path: "anchor-arguments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: workspaceURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        let workspacePath = workspaceURL.path(percentEncoded: false)

        let arguments = try AnchorMCPArguments(
            [
                "/Applications/AnchorMac.app/Contents/Helpers/AnchorMCPServer", "--workspace",
                workspacePath,
            ])
        #expect(arguments.workspacePath == workspacePath)

        for invalidPath in [
            "", ".", "relative/workspace", "~/workspace", workspacePath + "/absent",
            workspacePath + "\0suffix",
        ] {
            #expect(throws: AnchorMCPArguments.Failure.invalidWorkspace) {
                try AnchorMCPArguments(["AnchorMCPServer", "--workspace", invalidPath])
            }
        }
        let regularFileURL = workspaceURL.appending(path: "file.txt")
        try Data("file".utf8).write(to: regularFileURL)
        #expect(throws: AnchorMCPArguments.Failure.invalidWorkspace) {
            try AnchorMCPArguments(
                ["AnchorMCPServer", "--workspace", regularFileURL.path(percentEncoded: false)])
        }
    }

    @Test("missing duplicate and unknown arguments are refused")
    func malformedArgumentsAreRefused() {
        let malformedArguments = [
            [], ["AnchorMCPServer"], ["AnchorMCPServer", "--workspace"],
            ["AnchorMCPServer", "/"], ["AnchorMCPServer", "--unknown", "/"],
            ["AnchorMCPServer", "--workspace=/"],
            ["AnchorMCPServer", "--workspace", "/", "--workspace", "/"],
            ["AnchorMCPServer", "--workspace", "/", "--unknown"],
            ["AnchorMCPServer", "--workspace", "/", "extra"],
        ]
        for arguments in malformedArguments {
            #expect(throws: AnchorMCPArguments.Failure.invalidArguments) {
                try AnchorMCPArguments(arguments)
            }
        }
    }
}
