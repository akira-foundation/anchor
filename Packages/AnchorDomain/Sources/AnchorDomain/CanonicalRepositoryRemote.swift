import AnchorFoundation
import Foundation

public struct CanonicalRepositoryRemote: ValidatedRawValue, Hashable, CustomStringConvertible {
    public static var rawValueRequirement: String {
        "Repository remote is not in canonical host/path form"
    }

    public let rawValue: String

    public init?(rawValue: String) {
        guard let canonicalForm = Self.canonicalForm(of: rawValue), canonicalForm == rawValue else {
            return nil
        }

        self.rawValue = rawValue
    }

    public init?(gitRemote: String) {
        guard let canonicalForm = Self.canonicalForm(of: gitRemote) else { return nil }

        self.rawValue = canonicalForm
    }

    public var description: String { rawValue }

    private static func canonicalForm(of gitRemote: String) -> String? {
        let trimmedRemote = gitRemote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemote.isEmpty else { return nil }

        let transportFreeRemote = removingCredentials(from: removingScheme(from: trimmedRemote))
        let authorityAndPath = splitAuthorityFromPath(transportFreeRemote)
        guard let authorityAndPath else { return nil }

        let host = normalizedHost(of: authorityAndPath.authority)
        guard let host else { return nil }

        let path = normalizedPath(of: authorityAndPath.path)
        guard let path else { return nil }

        return "\(host)/\(path)"
    }

    private static func removingScheme(from remote: String) -> String {
        guard let separatorRange = remote.range(of: "://") else { return remote }

        return String(remote[separatorRange.upperBound...])
    }

    private static func removingCredentials(from remote: String) -> String {
        let pathStart = remote.firstIndex(of: "/") ?? remote.endIndex
        guard let credentialsSeparator = remote[..<pathStart].lastIndex(of: "@") else {
            return remote
        }

        return String(remote[remote.index(after: credentialsSeparator)...])
    }

    private static func splitAuthorityFromPath(
        _ remote: String
    ) -> (authority: String, path: String)? {
        let slashIndex = remote.firstIndex(of: "/")

        if let colonIndex = remote.firstIndex(of: ":"),
            slashIndex == nil || colonIndex < slashIndex!,
            !isPortDigits(remote[remote.index(after: colonIndex)..<(slashIndex ?? remote.endIndex)])
        {
            return (
                String(remote[..<colonIndex]),
                String(remote[remote.index(after: colonIndex)...])
            )
        }

        guard let slashIndex else { return nil }

        return (
            String(remote[..<slashIndex]),
            String(remote[remote.index(after: slashIndex)...])
        )
    }

    private static func isPortDigits(_ candidate: Substring) -> Bool {
        !candidate.isEmpty && candidate.allSatisfy(\.isNumber)
    }

    private static func normalizedHost(of authority: String) -> String? {
        var host = authority

        if let portSeparator = host.lastIndex(of: ":") {
            guard isPortDigits(host[host.index(after: portSeparator)...]) else { return nil }

            host = String(host[..<portSeparator])
        }

        guard !host.isEmpty, !host.contains("/"), host.contains(".") || host.contains("localhost")
        else {
            return nil
        }

        return host.lowercased()
    }

    private static func normalizedPath(of path: String) -> String? {
        var remainingPath = path

        while remainingPath.hasSuffix("/") {
            remainingPath.removeLast()
        }

        if remainingPath.hasSuffix(".git") {
            remainingPath.removeLast(4)
        }

        let segments = remainingPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.isEmpty, segments.allSatisfy({ !$0.isEmpty }) else { return nil }

        return segments.joined(separator: "/")
    }
}
