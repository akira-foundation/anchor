import Foundation

public enum FullTextQuery {
    public static func matchExpression(for queryText: String) -> String? {
        let words = queryText.split { !$0.isLetter && !$0.isNumber && $0 != "_" }

        guard !words.isEmpty else { return nil }

        return words.map { "\"\($0)\"" }.joined(separator: " ")
    }
}
