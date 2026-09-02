import Foundation

public enum InferenceReadiness: Sendable, Hashable {
    case ready
    case unavailable(String)
}

public struct InferenceRequest: Sendable, Hashable {
    public let window: InferenceWindow
    public let kinds: [String]

    public init(window: InferenceWindow, kinds: [String]) {
        self.window = window
        self.kinds = kinds
    }
}

public struct InferredStatement: Sendable, Hashable {
    public let kind: String
    public let summaryText: String

    public init(kind: String, summaryText: String) {
        self.kind = kind
        self.summaryText = summaryText
    }
}

public protocol StatementInferring: Sendable {
    func readiness() async -> InferenceReadiness
    func inferStatements(for request: InferenceRequest) async throws -> [InferredStatement]
}

extension InferredStatement {
    public static func usable(
        among statements: [InferredStatement], amongKinds kinds: [String]
    ) -> [InferredStatement] {
        let permitted = Set(kinds.map { $0.lowercased() })
        var seen: Set<InferredStatement> = []

        return statements.compactMap { statement -> InferredStatement? in
            let kind = statement.kind.lowercased()
            let summaryText = statement.summaryText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard permitted.contains(kind), !summaryText.isEmpty else { return nil }

            let usable = InferredStatement(kind: kind, summaryText: summaryText)

            return seen.insert(usable).inserted ? usable : nil
        }
    }
}
