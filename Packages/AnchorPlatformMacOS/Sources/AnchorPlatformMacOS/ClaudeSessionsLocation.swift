import Foundation

public enum ClaudeSessionsLocation {
    public static func directoryName(forWorkspaceAt workspaceURL: URL) -> String {
        String(
            workspaceURL.resolvingSymlinksInPath().path(percentEncoded: false).map { character in
                character == "/" || character == "." ? "-" : character
            }
        )
        .replacingOccurrences(of: "-$", with: "", options: .regularExpression)
    }

    public static func directoryURL(
        forWorkspaceAt workspaceURL: URL, under root: URL
    ) -> URL? {
        let wanted = directoryName(forWorkspaceAt: workspaceURL)
        let candidates =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? []

        return candidates.first {
            $0.lastPathComponent.caseInsensitiveCompare(wanted) == .orderedSame
        }
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
    }
}
