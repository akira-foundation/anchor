import AnchorDomain
import Foundation

public struct ConversationAuthoritySelector: Sendable {
    private static let acknowledgements: Set<String> = [
        "ok", "okay", "sim", "yes", "aprovado", "approved", "concordo", "agreed",
    ]
    private static let selectionPrefixes: Set<String> = ["opção", "opcao", "option"]
    private static let terminalPunctuation: Set<Character> = [".", "!", "?"]
    private static let decimalDigits: Set<Character> = Set("0123456789")

    public init() {}

    public func authorizedUnits(
        in conversationMessages: [ConversationMessage]
    ) -> [AuthorizedConversationUnit] {
        var authorizedUnits: [AuthorizedConversationUnit] = []

        for (messageIndex, conversationMessage) in conversationMessages.enumerated() {
            guard conversationMessage.role == .user else { continue }
            guard Self.hasSubstantiveContent(conversationMessage.content) else { continue }

            let normalizedReply = Self.normalizedReply(conversationMessage.content)

            if Self.acknowledgements.contains(normalizedReply) {
                guard
                    let authorizedUnit = Self.authorizedAcknowledgementUnit(
                        acknowledgement: conversationMessage,
                        at: messageIndex,
                        in: conversationMessages)
                else { continue }

                authorizedUnits.append(authorizedUnit)
                continue
            }

            if let selectedNumber = Self.selectedAlternativeNumber(in: normalizedReply) {
                guard
                    let authorizedUnit = Self.authorizedSelectionUnit(
                        selection: conversationMessage,
                        selectedNumber: selectedNumber,
                        at: messageIndex,
                        in: conversationMessages)
                else { continue }

                authorizedUnits.append(authorizedUnit)
                continue
            }

            guard
                let directUserUnit = AuthorizedConversationUnit(
                    fragmentsByMessageID: [conversationMessage.id: conversationMessage.content],
                    messageIDs: [conversationMessage.id])
            else { continue }

            authorizedUnits.append(directUserUnit)
        }

        return authorizedUnits
    }

    private static func authorizedAcknowledgementUnit(
        acknowledgement: ConversationMessage,
        at messageIndex: Int,
        in conversationMessages: [ConversationMessage]
    ) -> AuthorizedConversationUnit? {
        guard
            let assistantMessage = precedingAssistantIgnoringMetadata(
                before: messageIndex, in: conversationMessages)
        else { return nil }

        return AuthorizedConversationUnit(
            fragmentsByMessageID: [
                assistantMessage.id: assistantMessage.content,
                acknowledgement.id: acknowledgement.content,
            ],
            messageIDs: [assistantMessage.id, acknowledgement.id])
    }

    private static func authorizedSelectionUnit(
        selection: ConversationMessage,
        selectedNumber: Int,
        at messageIndex: Int,
        in conversationMessages: [ConversationMessage]
    ) -> AuthorizedConversationUnit? {
        guard
            let assistantMessage = precedingAssistantIgnoringMetadata(
                before: messageIndex, in: conversationMessages)
        else { return nil }
        guard
            let selectedFragment = uniquelySelectedFragment(
                numbered: selectedNumber, in: assistantMessage.content)
        else { return nil }

        return AuthorizedConversationUnit(
            fragmentsByMessageID: [
                assistantMessage.id: selectedFragment,
                selection.id: selection.content,
            ],
            messageIDs: [assistantMessage.id, selection.id])
    }

    private static func precedingAssistantIgnoringMetadata(
        before messageIndex: Int,
        in conversationMessages: [ConversationMessage]
    ) -> ConversationMessage? {
        guard messageIndex > conversationMessages.startIndex else { return nil }

        for precedingIndex in stride(
            from: messageIndex - 1,
            through: conversationMessages.startIndex,
            by: -1
        ) {
            let precedingMessage = conversationMessages[precedingIndex]

            switch precedingMessage.role {
            case .system, .tool:
                continue
            case .user:
                return nil
            case .assistant:
                guard hasSubstantiveContent(precedingMessage.content) else { return nil }

                return precedingMessage
            }
        }

        return nil
    }

    private static func normalizedReply(_ reply: String) -> String {
        var normalizedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        while let finalCharacter = normalizedReply.last,
            terminalPunctuation.contains(finalCharacter)
        {
            normalizedReply.removeLast()
        }

        return normalizedReply
    }

    private static func selectedAlternativeNumber(in normalizedReply: String) -> Int? {
        let replyParts = normalizedReply.components(separatedBy: " ")

        if replyParts.count == 1 {
            return decimalNumber(in: replyParts[0])
        }

        guard replyParts.count == 2 else { return nil }
        guard selectionPrefixes.contains(replyParts[0]) else { return nil }

        return decimalNumber(in: replyParts[1])
    }

    private static func decimalNumber(in digits: String) -> Int? {
        guard !digits.isEmpty else { return nil }
        guard digits.allSatisfy({ decimalDigits.contains($0) }) else { return nil }

        return Int(digits)
    }

    private static func uniquelySelectedFragment(
        numbered selectedNumber: Int,
        in assistantContent: String
    ) -> String? {
        let assistantLines = assistantContent.split(
            separator: "\n", omittingEmptySubsequences: false)
        var numberedAlternatives: [(number: Int, lines: [Substring])] = []
        var currentNumber: Int?
        var currentLines: [Substring] = []

        for assistantLine in assistantLines {
            if let alternativeNumber = numberedAlternativeNumber(in: assistantLine) {
                if let currentNumber {
                    numberedAlternatives.append((currentNumber, currentLines))
                }
                currentNumber = alternativeNumber
                currentLines = [assistantLine]
            } else {
                guard currentNumber != nil else { continue }

                currentLines.append(assistantLine)
            }
        }

        if let currentNumber {
            numberedAlternatives.append((currentNumber, currentLines))
        }

        let matchingAlternatives = numberedAlternatives.filter { $0.number == selectedNumber }

        guard matchingAlternatives.count == 1 else { return nil }

        return matchingAlternatives[0].lines.joined(separator: "\n")
    }

    private static func numberedAlternativeNumber(in line: Substring) -> Int? {
        guard let markerIndex = line.firstIndex(where: { !decimalDigits.contains($0) }) else {
            return nil
        }
        guard markerIndex != line.startIndex else { return nil }

        let marker = line[markerIndex]
        guard marker == "." || marker == ")" else { return nil }

        let spaceIndex = line.index(after: markerIndex)
        guard spaceIndex < line.endIndex, line[spaceIndex] == " " else { return nil }

        return decimalNumber(in: String(line[..<markerIndex]))
    }

    private static func hasSubstantiveContent(_ content: String) -> Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
