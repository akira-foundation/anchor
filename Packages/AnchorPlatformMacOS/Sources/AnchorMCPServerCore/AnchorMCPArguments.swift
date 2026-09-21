import Foundation

public struct AnchorMCPArguments: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case invalidArguments
        case invalidWorkspace
    }

    public let workspacePath: String

    public init(_ arguments: [String]) throws(Failure) {
        guard arguments.count == 3, arguments[1] == "--workspace" else {
            throw .invalidArguments
        }
        let workspacePath = arguments[2]
        guard workspacePath.hasPrefix("/"), !workspacePath.contains("\0") else {
            throw .invalidWorkspace
        }
        var isDirectory = ObjCBool(false)
        guard
            FileManager.default.fileExists(atPath: workspacePath, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw .invalidWorkspace }
        self.workspacePath = workspacePath
    }
}
