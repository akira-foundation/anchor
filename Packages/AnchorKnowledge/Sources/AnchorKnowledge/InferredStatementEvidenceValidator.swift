import AnchorDomain
import AnchorIntelligence
import Foundation

public enum InferenceCandidateRejectionReason: Sendable, Hashable {
    case invalidKind
    case emptySummary
    case missingSupportingMessage
    case unknownSupportingMessage
    case supportingMessagesCrossUnits
    case supportingMessagesDoNotMatchAuthorizedUnit
    case missingEvidence
    case evidenceIsNotLiteral
    case duplicate
}

public struct InferenceCandidateRejection: Sendable, Hashable {
    public let statement: InferredStatement
    public let reason: InferenceCandidateRejectionReason

    public init(statement: InferredStatement, reason: InferenceCandidateRejectionReason) {
        self.statement = statement
        self.reason = reason
    }
}

public struct InferenceCandidateAssessment: Sendable, Hashable {
    public let acceptedStatements: [InferredStatement]
    public let rejections: [InferenceCandidateRejection]

    public init(
        acceptedStatements: [InferredStatement],
        rejections: [InferenceCandidateRejection]
    ) {
        self.acceptedStatements = acceptedStatements
        self.rejections = rejections
    }
}

public struct InferredStatementEvidenceValidator: Sendable {
    private struct CandidateIdentity: Hashable {
        let kind: String
        let summaryText: String
        let supportingMessageIDs: [MessageID]
    }

    private static let permittedKinds = Set(KnowledgeEntryKind.allCases.map(\.rawValue))

    public init() {}

    public func assess(
        _ candidateStatements: [InferredStatement],
        in authorizedWindow: AuthorizedInferenceWindow
    ) -> InferenceCandidateAssessment {
        var acceptedStatements: [InferredStatement] = []
        var rejections: [InferenceCandidateRejection] = []
        var acceptedCandidateIdentities: Set<CandidateIdentity> = []

        for candidateStatement in candidateStatements {
            let normalizedKind = candidateStatement.kind.lowercased()

            guard Self.permittedKinds.contains(normalizedKind) else {
                rejections.append(
                    InferenceCandidateRejection(
                        statement: candidateStatement,
                        reason: .invalidKind))
                continue
            }

            let normalizedSummary = candidateStatement.summaryText.trimmingCharacters(
                in: .whitespacesAndNewlines)

            guard !normalizedSummary.isEmpty else {
                rejections.append(
                    InferenceCandidateRejection(
                        statement: candidateStatement,
                        reason: .emptySummary))
                continue
            }

            guard !candidateStatement.supportingMessageIDs.isEmpty else {
                rejections.append(
                    InferenceCandidateRejection(
                        statement: candidateStatement,
                        reason: .missingSupportingMessage))
                continue
            }

            guard
                candidateStatement.supportingMessageIDs.allSatisfy({
                    authorizedWindow.fragmentsByMessageID[$0] != nil
                })
            else {
                rejections.append(
                    InferenceCandidateRejection(
                        statement: candidateStatement,
                        reason: .unknownSupportingMessage))
                continue
            }

            let supportingUnitIndices = candidateStatement.supportingMessageIDs.compactMap {
                authorizedWindow.unitIndexByMessageID[$0]
            }

            guard
                supportingUnitIndices.count == candidateStatement.supportingMessageIDs.count,
                Set(supportingUnitIndices).count == 1
            else {
                rejections.append(
                    InferenceCandidateRejection(
                        statement: candidateStatement,
                        reason: .supportingMessagesCrossUnits))
                continue
            }

            guard
                let supportingUnitIndex = supportingUnitIndices.first,
                candidateStatement.supportingMessageIDs
                    == authorizedWindow.messageIDsByUnitIndex[supportingUnitIndex]
            else {
                rejections.append(
                    InferenceCandidateRejection(
                        statement: candidateStatement,
                        reason: .supportingMessagesDoNotMatchAuthorizedUnit))
                continue
            }

            guard
                !candidateStatement.evidenceText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            else {
                rejections.append(
                    InferenceCandidateRejection(
                        statement: candidateStatement,
                        reason: .missingEvidence))
                continue
            }

            guard
                candidateStatement.supportingMessageIDs.contains(where: { messageID in
                    authorizedWindow.fragmentsByMessageID[messageID]?.contains(
                        candidateStatement.evidenceText) == true
                })
            else {
                rejections.append(
                    InferenceCandidateRejection(
                        statement: candidateStatement,
                        reason: .evidenceIsNotLiteral))
                continue
            }

            let candidateIdentity = CandidateIdentity(
                kind: normalizedKind,
                summaryText: normalizedSummary,
                supportingMessageIDs: candidateStatement.supportingMessageIDs)

            guard acceptedCandidateIdentities.insert(candidateIdentity).inserted else {
                rejections.append(
                    InferenceCandidateRejection(
                        statement: candidateStatement,
                        reason: .duplicate))
                continue
            }

            acceptedStatements.append(
                InferredStatement(
                    kind: normalizedKind,
                    summaryText: normalizedSummary,
                    supportingMessageIDs: candidateStatement.supportingMessageIDs,
                    evidenceText: candidateStatement.evidenceText))
        }

        return InferenceCandidateAssessment(
            acceptedStatements: acceptedStatements,
            rejections: rejections)
    }
}
