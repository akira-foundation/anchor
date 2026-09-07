import Foundation

public struct InferenceWindow: Sendable, Hashable {
    public static let defaultCharacterBudget = 4_000

    public let text: String
    public let omittedCharacterCount: Int

    public init(over conversation: String, keeping characterBudget: Int) {
        let budget = max(0, characterBudget)

        guard conversation.count > budget else {
            self.text = conversation
            self.omittedCharacterCount = 0
            return
        }

        self.text = String(conversation.suffix(budget))
        self.omittedCharacterCount = conversation.count - budget
    }

    public var wasShortened: Bool { omittedCharacterCount > 0 }
}
