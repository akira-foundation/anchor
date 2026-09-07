import Foundation

struct InferenceEvidenceFragment: Sendable, Equatable {
    let number: Int
    let text: String
}

enum InferenceEvidenceFragmenter {
    static func markdownQuoteLines(in evidenceText: String) -> [String] {
        var quotedSegments: [String] = []
        var currentSegment = ""
        for line in evidenceText.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasPrefix(">") else {
                if !currentSegment.isEmpty { quotedSegments.append(currentSegment) }
                currentSegment = ""
                continue
            }
            let quotedText = String(trimmedLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !quotedText.isEmpty else {
                if !currentSegment.isEmpty { quotedSegments.append(currentSegment) }
                currentSegment = ""
                continue
            }
            currentSegment = [currentSegment, quotedText].filter { !$0.isEmpty }.joined(
                separator: " ")
            if quotedText.last.map({ ".!?".contains($0) }) == true {
                quotedSegments.append(currentSegment)
                currentSegment = ""
            }
        }
        if !currentSegment.isEmpty { quotedSegments.append(currentSegment) }
        return quotedSegments
    }

    static func fragments(in evidenceText: String) -> [InferenceEvidenceFragment] {
        var candidates: [FragmentCandidate] = []
        evidenceText.enumerateSubstrings(
            in: evidenceText.startIndex..<evidenceText.endIndex,
            options: .bySentences
        ) { substring, substringRange, _, _ in
            guard let substring else { return }
            let trimmedSubstring = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSubstring.isEmpty else { return }
            candidates.append(FragmentCandidate(range: substringRange, text: trimmedSubstring))
        }
        let groupedCandidates = candidates.reduce(into: [FragmentCandidate]()) {
            groupedCandidates, candidate in
            guard candidate.text.hasPrefix(">"), let previous = groupedCandidates.last,
                previous.text.hasSuffix(":") || previous.text.contains("\n>")
            else {
                groupedCandidates.append(candidate)
                return
            }
            let groupedRange = previous.range.lowerBound..<candidate.range.upperBound
            groupedCandidates[groupedCandidates.count - 1] = FragmentCandidate(
                range: groupedRange,
                text: evidenceText[groupedRange].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return groupedCandidates.enumerated().map { index, candidate in
            InferenceEvidenceFragment(number: index + 1, text: candidate.text)
        }
    }

    static func precedingFragment(
        for fragment: InferenceEvidenceFragment, among fragments: [InferenceEvidenceFragment]
    ) -> InferenceEvidenceFragment? {
        guard let fragmentIndex = fragments.firstIndex(of: fragment), fragmentIndex > 0 else {
            return nil
        }
        return fragments[fragmentIndex - 1]
    }

    private struct FragmentCandidate {
        let range: Range<String.Index>
        let text: String
    }
}
