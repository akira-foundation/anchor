import AnchorDomain
import AnchorIntelligence

public struct AuthorizedInferenceWindow: Sendable, Equatable {
    public let inferenceWindow: InferenceWindow
    public let fragmentsByMessageID: [MessageID: String]
    public let unitIndexByMessageID: [MessageID: Int]
    public let messageIDsByUnitIndex: [Int: [MessageID]]

    public var evidenceReferences: [InferenceEvidenceReference] {
        messageIDsByUnitIndex.keys.sorted().compactMap { unitIndex in
            guard let messageIDs = messageIDsByUnitIndex[unitIndex],
                let firstMessageID = messageIDs.first,
                let evidenceText = fragmentsByMessageID[firstMessageID]
            else { return nil }

            let confirmationText = messageIDs.dropFirst().compactMap {
                fragmentsByMessageID[$0]
            }.joined(separator: "\n")

            return InferenceEvidenceReference(
                number: unitIndex + 1, supportingMessageIDs: messageIDs,
                evidenceText: evidenceText,
                confirmationText: confirmationText.isEmpty ? nil : confirmationText)
        }
    }

    public init(units: [AuthorizedConversationUnit], characterBudget: Int) {
        let budget = max(0, characterBudget)
        let formattedUnits = units.map(Self.formattedUnit)
        let completeConversation = formattedUnits.joined(separator: "\n")

        guard let newestUnit = units.last, let newestText = formattedUnits.last else {
            inferenceWindow = InferenceWindow(text: "", omittedCharacterCount: 0)
            fragmentsByMessageID = [:]
            unitIndexByMessageID = [:]
            messageIDsByUnitIndex = [:]
            return
        }

        if newestText.count > budget {
            let truncatedUnit = Self.truncatedUnit(
                newestUnit, unitIndex: units.index(before: units.endIndex), budget: budget)
            let olderCharacterCount = completeConversation.count - newestText.count

            inferenceWindow = InferenceWindow(
                text: truncatedUnit?.text ?? "",
                omittedCharacterCount: olderCharacterCount
                    + (truncatedUnit?.omittedCharacterCount ?? newestText.count))
            fragmentsByMessageID = truncatedUnit?.fragmentsByMessageID ?? [:]
            unitIndexByMessageID = truncatedUnit?.unitIndexByMessageID ?? [:]
            messageIDsByUnitIndex = [:]
            return
        }

        var selectedStartIndex = units.index(before: units.endIndex)
        var selectedCharacterCount = newestText.count

        while selectedStartIndex > units.startIndex {
            let precedingIndex = units.index(before: selectedStartIndex)
            let precedingCost = formattedUnits[precedingIndex].count + 1

            guard selectedCharacterCount + precedingCost <= budget else { break }

            selectedStartIndex = precedingIndex
            selectedCharacterCount += precedingCost
        }

        let selectedText = formattedUnits[selectedStartIndex...].joined(separator: "\n")
        var selectedFragments: [MessageID: String] = [:]
        var selectedUnitIndices: [MessageID: Int] = [:]
        var selectedMessageIDsByUnitIndex: [Int: [MessageID]] = [:]

        for unitIndex in selectedStartIndex..<units.endIndex {
            let unit = units[unitIndex]
            selectedMessageIDsByUnitIndex[unitIndex] = unit.messageIDs

            for messageID in unit.messageIDs {
                selectedFragments[messageID] = unit.fragmentsByMessageID[messageID]
                selectedUnitIndices[messageID] = unitIndex
            }
        }

        inferenceWindow = InferenceWindow(
            text: selectedText,
            omittedCharacterCount: completeConversation.count - selectedText.count)
        fragmentsByMessageID = selectedFragments
        unitIndexByMessageID = selectedUnitIndices
        messageIDsByUnitIndex = selectedMessageIDsByUnitIndex
    }

    private struct TruncatedUnit {
        let text: String
        let omittedCharacterCount: Int
        let fragmentsByMessageID: [MessageID: String]
        let unitIndexByMessageID: [MessageID: Int]
    }

    private static func formattedUnit(_ unit: AuthorizedConversationUnit) -> String {
        let messages = unit.messageIDs.map { messageID in
            formattedMessage(
                id: messageID,
                content: unit.fragmentsByMessageID[messageID] ?? "")
        }.joined(separator: "\n")

        return formattedUnit(messages: messages)
    }

    private static func formattedUnit(messages: String) -> String {
        "<unit>\n\(messages)\n</unit>"
    }

    private static func formattedMessage(id: MessageID, content: String) -> String {
        "<message id=\"\(id.rawValue)\" role=\"user\">\n\(content)\n</message>"
    }

    private static func truncatedUnit(
        _ unit: AuthorizedConversationUnit,
        unitIndex: Int,
        budget: Int
    ) -> TruncatedUnit? {
        var retainedCounts = unit.messageIDs.map { messageID in
            let contentCount = unit.fragmentsByMessageID[messageID]?.count ?? 0
            let shortestTruncationCount =
                1
                + omissionMarker(omittedCharacterCount: contentCount - 1).count

            return contentCount <= shortestTruncationCount ? contentCount : 1
        }

        guard formattedTruncatedUnit(unit, retainedCounts: retainedCounts).count <= budget else {
            return nil
        }

        for messageIndex in unit.messageIDs.indices.reversed() {
            let messageID = unit.messageIDs[messageIndex]
            let contentCount = unit.fragmentsByMessageID[messageID]?.count ?? 0

            guard contentCount > retainedCounts[messageIndex] else { continue }

            retainedCounts[messageIndex] = largestRetainedCount(
                for: messageIndex,
                upTo: contentCount,
                in: unit,
                retainedCounts: retainedCounts,
                budget: budget)
        }

        var retainedFragments: [MessageID: String] = [:]
        var unitIndices: [MessageID: Int] = [:]
        var omittedCharacterCount = 0

        for (messageIndex, messageID) in unit.messageIDs.enumerated() {
            let content = unit.fragmentsByMessageID[messageID] ?? ""
            let retainedCount = retainedCounts[messageIndex]

            retainedFragments[messageID] = String(content.suffix(retainedCount))
            unitIndices[messageID] = unitIndex
            omittedCharacterCount += content.count - retainedCount
        }

        return TruncatedUnit(
            text: formattedTruncatedUnit(unit, retainedCounts: retainedCounts),
            omittedCharacterCount: omittedCharacterCount,
            fragmentsByMessageID: retainedFragments,
            unitIndexByMessageID: unitIndices)
    }

    private static func largestRetainedCount(
        for messageIndex: Int,
        upTo contentCount: Int,
        in unit: AuthorizedConversationUnit,
        retainedCounts: [Int],
        budget: Int
    ) -> Int {
        var candidateCounts = retainedCounts
        candidateCounts[messageIndex] = contentCount

        if formattedTruncatedUnit(unit, retainedCounts: candidateCounts).count <= budget {
            return contentCount
        }

        var lowerBound = retainedCounts[messageIndex]
        var upperBound = contentCount - 1

        while lowerBound < upperBound {
            let candidateCount = lowerBound + (upperBound - lowerBound + 1) / 2
            candidateCounts[messageIndex] = candidateCount

            if formattedTruncatedUnit(unit, retainedCounts: candidateCounts).count <= budget {
                lowerBound = candidateCount
            } else {
                upperBound = candidateCount - 1
            }
        }

        return lowerBound
    }

    private static func formattedTruncatedUnit(
        _ unit: AuthorizedConversationUnit,
        retainedCounts: [Int]
    ) -> String {
        let messages = unit.messageIDs.enumerated().map { messageIndex, messageID in
            let content = unit.fragmentsByMessageID[messageID] ?? ""
            let retainedCount = retainedCounts[messageIndex]
            let omittedCount = content.count - retainedCount
            let marker = omissionMarker(omittedCharacterCount: omittedCount)

            return formattedMessage(
                id: messageID,
                content: marker + content.suffix(retainedCount))
        }.joined(separator: "\n")

        return formattedUnit(messages: messages)
    }

    private static func omissionMarker(omittedCharacterCount: Int) -> String {
        omittedCharacterCount > 0
            ? "<omitted characters=\"\(omittedCharacterCount)\"/>"
            : ""
    }
}
