import AnchorDomain
import Foundation
import Testing

@testable import AnchorKnowledge

@Suite("Projecting structured extraction content as text")
struct KnowledgeExtractionContentTests {
    @Test("conversation content keeps the role-prefixed text projection")
    func conversationContentKeepsRolePrefixedTextProjection() {
        let sessionID = SessionID()
        let instant = Date(timeIntervalSince1970: 1_000)
        let messages = [
            ConversationMessage(
                id: MessageID(),
                sessionID: sessionID,
                role: .system,
                content: "System context",
                timestamp: instant
            ),
            ConversationMessage(
                id: MessageID(),
                sessionID: sessionID,
                role: .user,
                content: "DECISION: preserve the messages",
                timestamp: instant.addingTimeInterval(1)
            ),
        ]

        #expect(
            KnowledgeExtractionContent.conversation(messages).text
                == "system: System context\nuser: DECISION: preserve the messages"
        )
    }
}
