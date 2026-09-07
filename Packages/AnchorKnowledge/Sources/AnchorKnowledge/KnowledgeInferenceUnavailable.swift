import Foundation

public struct KnowledgeInferenceUnavailable: Error, Sendable, Hashable, CustomStringConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}
