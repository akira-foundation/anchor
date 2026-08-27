enum SuperpowersArtifactLocation: String, CaseIterable {
    case plans = "docs/superpowers/plans"
    case specs = "docs/superpowers/specs"
    case brainstorms = ".superpowers/brainstorm"
    case reviews = ".superpowers/sdd"

    var canonicalPath: String { rawValue }

    var pathsOnDisk: [String] {
        guard rawValue.hasPrefix("docs/") else { return [rawValue] }

        return [rawValue, "D" + rawValue.dropFirst()]
    }
}
