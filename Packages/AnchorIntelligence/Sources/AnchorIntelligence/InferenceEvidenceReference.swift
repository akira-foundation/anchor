import AnchorDomain
import Foundation

public struct InferenceEvidenceReference: Sendable, Hashable {
    public let number: Int
    public let supportingMessageIDs: [MessageID]
    public let evidenceText: String
    public let confirmationText: String?

    public init?(
        number: Int,
        supportingMessageIDs: [MessageID],
        evidenceText: String,
        confirmationText: String? = nil
    ) {
        guard number > 0, !supportingMessageIDs.isEmpty,
            Set(supportingMessageIDs).count == supportingMessageIDs.count,
            !evidenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        self.number = number
        self.supportingMessageIDs = supportingMessageIDs
        self.evidenceText = evidenceText
        self.confirmationText = confirmationText
    }

    func statement(kind: String, summaryText: String) -> InferredStatement {
        InferredStatement(
            kind: kind, summaryText: summaryText,
            supportingMessageIDs: supportingMessageIDs, evidenceText: evidenceText)
    }
}
