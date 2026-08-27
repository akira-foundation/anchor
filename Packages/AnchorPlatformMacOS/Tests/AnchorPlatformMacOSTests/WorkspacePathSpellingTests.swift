import Testing

@testable import AnchorPlatformMacOS

@Suite("Workspace path spelling")
struct WorkspacePathSpellingTests {
    @Test("a docs path may be spelled either way on disk")
    func aDocsPathMayBeSpelledEitherWayOnDisk() {
        #expect(
            WorkspacePathSpelling.spellingsOnDisk(of: "docs/superpowers/plans") == [
                "docs/superpowers/plans", "Docs/superpowers/plans",
            ]
        )
    }

    @Test("the canonical spelling comes first, because it is what the plugin writes")
    func theCanonicalSpellingComesFirst() {
        #expect(WorkspacePathSpelling.spellingsOnDisk(of: "docs/a.md").first == "docs/a.md")
    }

    @Test(
        "a path that does not start with docs has one spelling",
        arguments: [".superpowers/sdd", "graphify-out/graph.json", "README.md", "documents/a.md"]
    )
    func aPathThatDoesNotStartWithDocsHasOneSpelling(_ path: String) {
        #expect(WorkspacePathSpelling.spellingsOnDisk(of: path) == [path])
    }

    @Test("only the leading docs segment is respelled")
    func onlyTheLeadingDocsSegmentIsRespelled() {
        #expect(
            WorkspacePathSpelling.spellingsOnDisk(of: "docs/docs/a.md").last == "Docs/docs/a.md"
        )
    }
}
