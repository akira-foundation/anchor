import AnchorDomain
import AnchorIntelligence
import Testing

@testable import AnchorKnowledge

struct AuthorizedEvidenceReferenceTests {
    @Test("dropped older units never enter the reference catalog")
    func droppedOlderUnitsNeverEnterCatalog() throws {
        let olderID = MessageID()
        let proposalID = MessageID()
        let confirmationID = MessageID()
        let older = try #require(
            AuthorizedConversationUnit(
                fragmentsByMessageID: [olderID: String(repeating: "old", count: 200)],
                messageIDs: [olderID]))
        let confirmed = try #require(
            AuthorizedConversationUnit(
                fragmentsByMessageID: [proposalID: "Keep it local", confirmationID: "yes"],
                messageIDs: [proposalID, confirmationID]))
        let references = AuthorizedInferenceWindow(
            units: [older, confirmed], characterBudget: 250
        ).evidenceReferences

        #expect(references.count == 1)
        #expect(references.map(\.number) == [2])
        #expect(references.map(\.supportingMessageIDs) == [[proposalID, confirmationID]])
        #expect(references.map(\.evidenceText) == ["Keep it local"])
    }

    @Test("retained units expose evidence and confirmation without losing support")
    func retainedUnitsExposeCompleteSupport() throws {
        let proposalID = MessageID()
        let confirmationID = MessageID()
        let unit = try #require(
            AuthorizedConversationUnit(
                fragmentsByMessageID: [proposalID: "Keep it local", confirmationID: "yes"],
                messageIDs: [proposalID, confirmationID]))
        let window = AuthorizedInferenceWindow(units: [unit], characterBudget: 500)

        let reference = try #require(window.evidenceReferences.first)

        #expect(window.evidenceReferences.count == 1)
        #expect(reference.number == 1)
        #expect(reference.evidenceText == "Keep it local")
        #expect(reference.confirmationText == "yes")
        #expect(reference.supportingMessageIDs == [proposalID, confirmationID])
    }

    @Test("a truncated proposal never exposes its suffix as authorized evidence")
    func truncatedProposalNeverExposesSuffixAsAuthorizedEvidence() throws {
        let messageID = MessageID()
        let unit = try #require(
            AuthorizedConversationUnit(
                fragmentsByMessageID: [
                    messageID: "Unapproved proposal: " + String(repeating: "a", count: 500)
                        + "Always publish automatically."
                ],
                messageIDs: [messageID]))
        let window = AuthorizedInferenceWindow(units: [unit], characterBudget: 150)

        #expect(window.inferenceWindow.text.contains("<omitted"))
        #expect(window.inferenceWindow.text.contains("Always publish automatically."))
        #expect(!window.inferenceWindow.text.contains("Unapproved proposal:"))
        #expect(window.evidenceReferences.isEmpty)
        #expect(
            AuthorizedInferenceWindow(units: [unit], characterBudget: 0).evidenceReferences.isEmpty)
    }

    @Test("truncation of either confirmed message excludes the entire unit", arguments: [0, 1])
    func truncationOfEitherConfirmedMessageExcludesEntireUnit(truncatedMessageIndex: Int) throws {
        let messageIDs = [MessageID(), MessageID()]
        let fragments = ["Keep it local", "Approved"].enumerated().map { messageIndex, content in
            messageIndex == truncatedMessageIndex
                ? String(repeating: "context ", count: 100) + content : content
        }
        let unit = try #require(
            AuthorizedConversationUnit(
                fragmentsByMessageID: Dictionary(uniqueKeysWithValues: zip(messageIDs, fragments)),
                messageIDs: messageIDs))
        let window = AuthorizedInferenceWindow(units: [unit], characterBudget: 250)

        #expect(window.inferenceWindow.text.contains("<omitted"))
        #expect(window.inferenceWindow.text.contains("Keep it local"))
        #expect(window.inferenceWindow.text.contains("Approved"))
        #expect(window.evidenceReferences.isEmpty)
    }
}
