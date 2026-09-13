import AnchorDomain
import Foundation

public struct AuthorizedConversationUnit: Sendable, Equatable {
    public let fragmentsByMessageID: [MessageID: String]
    public let messageIDs: [MessageID]

    public init?(
        fragmentsByMessageID: [MessageID: String],
        messageIDs: [MessageID]
    ) {
        guard !messageIDs.isEmpty else { return nil }
        guard Set(messageIDs).count == messageIDs.count else { return nil }
        guard Set(fragmentsByMessageID.keys) == Set(messageIDs) else { return nil }
        guard
            fragmentsByMessageID.values.allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else { return nil }

        self.fragmentsByMessageID = fragmentsByMessageID
        self.messageIDs = messageIDs
    }
}
