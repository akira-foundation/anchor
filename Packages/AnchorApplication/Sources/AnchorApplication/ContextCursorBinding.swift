import Foundation

public struct ContextCursorBinding: Sendable, Equatable {
    public let workspacePath: String
    public let generation: ContextReadGeneration

    public init(workspaceURL: URL, generation: ContextReadGeneration) {
        workspacePath = workspaceURL.standardizedFileURL.resolvingSymlinksInPath()
            .path(percentEncoded: false)
        self.generation = generation
    }
}
