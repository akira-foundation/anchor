import Foundation

enum ArtifactSummaryLine {
    static func firstNonEmptyLine(of content: Data) -> String? {
        String(decoding: content, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
