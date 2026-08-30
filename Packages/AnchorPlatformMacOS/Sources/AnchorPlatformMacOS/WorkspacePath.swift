import Foundation

public enum WorkspacePath {
    public static func comparable(_ url: URL) -> String {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            .path(percentEncoded: false)

        return resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    }

    static func relativePath(of absolutePath: String, under workspaceURL: URL) -> String? {
        let root = canonicalPath(workspaceURL.resolvingSymlinksInPath().path())
        let prefix = root.hasSuffix("/") ? root : root + "/"
        let event = canonicalPath(absolutePath)
        guard event.hasPrefix(prefix) else { return nil }

        return String(event.dropFirst(prefix.count))
    }

    static func isWatched(_ relativePath: String) -> Bool {
        let watchedPrefixes =
            SuperpowersArtifactLocation.allCases.flatMap(\.pathsOnDisk)
            + [GraphifyArtifactProvider.outputDirectory]

        return watchedPrefixes.contains { relativePath.hasPrefix($0 + "/") }
    }

    private static func canonicalPath(_ path: String) -> String {
        guard path.hasPrefix("/private/") else { return path }

        return String(path.dropFirst("/private".count))
    }
}
