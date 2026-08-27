enum WorkspacePathSpelling {
    private static let canonicalDocsPrefix = "docs/"
    private static let capitalizedDocsPrefix = "Docs/"

    static func spellingsOnDisk(of canonicalPath: String) -> [String] {
        guard canonicalPath.hasPrefix(canonicalDocsPrefix) else { return [canonicalPath] }

        let withoutPrefix = canonicalPath.dropFirst(canonicalDocsPrefix.count)

        return [canonicalPath, capitalizedDocsPrefix + withoutPrefix]
    }
}
