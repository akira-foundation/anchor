import AnchorDomain

enum SuperpowersArtifactLocation: String, CaseIterable {
    case plans = "docs/superpowers/plans"
    case specs = "docs/superpowers/specs"
    case brainstorms = ".superpowers/brainstorm"
    case reviews = ".superpowers/sdd"

    var canonicalPath: String { rawValue }

    var vouchedKnowledgeKind: KnowledgeEntryKind {
        switch self {
        case .reviews: .risk
        case .specs: .architecture
        case .plans, .brainstorms: .summary
        }
    }

    static func location(forCanonicalPath canonicalPath: String) -> SuperpowersArtifactLocation? {
        allCases.first { $0.canonicalPath == canonicalPath }
    }

    var pathsOnDisk: [String] {
        WorkspacePathSpelling.spellingsOnDisk(of: rawValue)
    }
}
