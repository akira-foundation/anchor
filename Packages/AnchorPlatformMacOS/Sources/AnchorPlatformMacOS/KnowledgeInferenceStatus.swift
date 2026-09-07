import Foundation

public enum KnowledgeInferenceStatus: Sendable, Hashable {
    case disabled
    case ready
    case unavailable(String)
}
