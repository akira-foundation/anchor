import Foundation

public struct ContextReadModelLocation: Sendable {
    public let databaseURL: URL
    public let rebuildMarkerURL: URL
    public let generationURL: URL

    public init(supportDirectoryURL: URL) {
        databaseURL = supportDirectoryURL.appending(path: "context.sqlite")
        rebuildMarkerURL = supportDirectoryURL.appending(path: "context-rebuild-required")
        generationURL = supportDirectoryURL.appending(path: "context-generation.json")
    }
}
