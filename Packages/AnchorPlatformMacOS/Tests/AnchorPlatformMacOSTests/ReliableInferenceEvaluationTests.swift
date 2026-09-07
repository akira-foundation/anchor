import AnchorDomain
import AnchorIntelligence
import AnchorKnowledge
import Foundation
import Testing

@testable import AnchorPlatformMacOS

private let reliableInferenceEvaluationIsAllowed = {
    let environment = ProcessInfo.processInfo.environment

    return environment["ANCHOR_INFERENCE_TESTS"] != nil
        && environment["ANCHOR_INFERENCE_EVALUATION_MANIFEST"] != nil
}()

struct ExpectedKnowledge: Decodable {
    let kind: KnowledgeEntryKind
    let coverageCategory: CoverageCategory
    let supportingMessageIDs: Set<MessageID>
}

enum CoverageCategory: String, Decodable, CaseIterable {
    case decision
    case risk
    case preference
}

struct EvaluationSession: Decodable {
    let provider: AgentProvider
    let transcriptPath: String
    let expectedKnowledge: [ExpectedKnowledge]
    let forbiddenMessageIDs: Set<MessageID>
    let negativeCoverageCategories: Set<CoverageCategory>
}

@Suite(
    "Reliable inference against a local labelled corpus",
    .enabled(if: reliableInferenceEvaluationIsAllowed), .serialized
)
struct ReliableInferenceEvaluationTests {
    @Test("three passes meet the precision, recall, and evidence gates")
    func threePassesMeetPrecisionRecallAndEvidenceGates() async throws {
        let evaluationSessions = try loadEvaluationSessions()

        try requireCoverage(in: evaluationSessions)

        for passNumber in 1...3 {
            let startedAt = ContinuousClock.now
            let measurement = try await measureInference(in: evaluationSessions)
            let elapsed = startedAt.duration(to: .now)

            print(
                "inference-evaluation pass=\(passNumber) "
                    + "expected=\(measurement.expectedCount) "
                    + "matched=\(measurement.matchedExpectedCount) "
                    + "false-positives=\(measurement.falsePositiveCount) "
                    + "forbidden-support=\(measurement.forbiddenSupportCount) "
                    + "elapsed=\(elapsed)")
            #expect(measurement.falsePositiveCount == 0)
            #expect(
                Double(measurement.matchedExpectedCount)
                    / Double(measurement.expectedCount) >= 2.0 / 3.0)
            #expect(measurement.forbiddenSupportCount == 0)
        }
    }
}

private struct EvaluationMeasurement {
    let falsePositiveCount: Int
    let matchedExpectedCount: Int
    let expectedCount: Int
    let forbiddenSupportCount: Int
}

private struct KnowledgeIdentity: Hashable {
    let kind: KnowledgeEntryKind
    let supportingMessageIDs: Set<MessageID>
}

enum EvaluationFailure: Error {
    case unavailableConfiguration
    case invalidManifest
    case incompleteCoverage
    case unreadableTranscript
    case ambiguousTranscript
    case unsupportedProvider
    case labelsAbsentFromTranscript
    case expectedSupportUnavailableToInference
    case forbiddenSupportUnavailableToInference
}

private func loadEvaluationSessions() throws -> [EvaluationSession] {
    guard
        let manifestPath = ProcessInfo.processInfo.environment[
            "ANCHOR_INFERENCE_EVALUATION_MANIFEST"]
    else { throw EvaluationFailure.unavailableConfiguration }

    do {
        let manifestBytes = try Data(contentsOf: URL(filePath: manifestPath))
        let evaluationSessions = try JSONDecoder().decode(
            [EvaluationSession].self, from: manifestBytes)

        guard !evaluationSessions.isEmpty else { throw EvaluationFailure.invalidManifest }

        return evaluationSessions
    } catch is EvaluationFailure {
        throw EvaluationFailure.invalidManifest
    } catch {
        throw EvaluationFailure.invalidManifest
    }
}

func requireCoverage(in evaluationSessions: [EvaluationSession]) throws {
    let requiredCategories = Set(CoverageCategory.allCases)
    let positiveCategories = Set(
        evaluationSessions.flatMap(\.expectedKnowledge).map(\.coverageCategory))
    let negativeCategories = Set(
        evaluationSessions.flatMap(\.negativeCoverageCategories))
    let expectations = evaluationSessions.flatMap(\.expectedKnowledge)

    guard positiveCategories == requiredCategories,
        negativeCategories == requiredCategories,
        evaluationSessions.allSatisfy({ evaluationSession in
            evaluationSession.forbiddenMessageIDs.isEmpty
                == evaluationSession.negativeCoverageCategories.isEmpty
        }),
        expectations.allSatisfy({ !$0.supportingMessageIDs.isEmpty }),
        expectations.filter({ $0.coverageCategory == .preference })
            .allSatisfy({ $0.kind == .decision })
    else { throw EvaluationFailure.incompleteCoverage }

    for evaluationSession in evaluationSessions {
        let expectedIdentities = evaluationSession.expectedKnowledge.map {
            KnowledgeIdentity(
                kind: $0.kind, supportingMessageIDs: $0.supportingMessageIDs)
        }
        let supportingMessageIDs = Set(
            evaluationSession.expectedKnowledge.flatMap(\.supportingMessageIDs))

        guard Set(expectedIdentities).count == expectedIdentities.count,
            supportingMessageIDs.isDisjoint(with: evaluationSession.forbiddenMessageIDs)
        else { throw EvaluationFailure.invalidManifest }
    }
}

private func measureInference(
    in evaluationSessions: [EvaluationSession]
) async throws -> EvaluationMeasurement {
    var falsePositiveCount = 0
    var matchedExpectedCount = 0
    var expectedCount = 0
    var forbiddenSupportCount = 0

    for evaluationSession in evaluationSessions {
        let transcriptSource = try loadTranscriptSource(for: evaluationSession)
        let transcript = try parseTranscript(
            from: transcriptSource, describedBy: evaluationSession)
        let labelledMessageIDs = Set(
            evaluationSession.expectedKnowledge.flatMap(\.supportingMessageIDs)
        )
        .union(evaluationSession.forbiddenMessageIDs)
        let transcriptMessageIDs = Set(transcript.messages.map(\.id))

        guard labelledMessageIDs.isSubset(of: transcriptMessageIDs) else {
            throw EvaluationFailure.labelsAbsentFromTranscript
        }
        let authorizedWindow = AuthorizedInferenceWindow(
            units: ConversationAuthoritySelector().authorizedUnits(
                in: transcript.inConversationOrder.messages),
            characterBudget: InferenceWindow.defaultCharacterBudget)
        let expectedSupportIsAvailable = expectedSupportsMatchCompleteAuthorizedUnits(
            evaluationSession.expectedKnowledge,
            in: authorizedWindow)

        guard expectedSupportIsAvailable else {
            throw EvaluationFailure.expectedSupportUnavailableToInference
        }
        try requireForbiddenEvidenceInWindow(
            evaluationSession.forbiddenMessageIDs, in: authorizedWindow)

        let inferredEntries = try await InferredKnowledgeExtractor(
            inference: OnDeviceStatementInference()
        ).extractEntries(
            for: KnowledgeExtractionRequest(
                messages: transcript.inConversationOrder.messages,
                projectID: transcript.session.projectID,
                source: .session(transcript.session.id),
                sourceContentHash: ContentHash.digest(of: transcriptSource),
                extractedAt: Date(timeIntervalSince1970: 0)))
        let expectedIdentities = Set(
            evaluationSession.expectedKnowledge.map {
                KnowledgeIdentity(
                    kind: $0.kind, supportingMessageIDs: $0.supportingMessageIDs)
            })
        let inferredIdentities = Set(
            inferredEntries.map {
                KnowledgeIdentity(
                    kind: $0.kind, supportingMessageIDs: Set($0.supportingMessageIDs))
            })

        expectedCount += expectedIdentities.count
        matchedExpectedCount += expectedIdentities.intersection(inferredIdentities).count
        falsePositiveCount +=
            inferredEntries.filter {
                !expectedIdentities.contains(
                    KnowledgeIdentity(
                        kind: $0.kind, supportingMessageIDs: Set($0.supportingMessageIDs)))
            }.count
        forbiddenSupportCount += inferredEntries.reduce(into: 0) { count, inferredEntry in
            count +=
                Set(inferredEntry.supportingMessageIDs)
                .intersection(evaluationSession.forbiddenMessageIDs).count
        }
    }

    return EvaluationMeasurement(
        falsePositiveCount: falsePositiveCount,
        matchedExpectedCount: matchedExpectedCount,
        expectedCount: expectedCount,
        forbiddenSupportCount: forbiddenSupportCount)
}

func expectedSupportsMatchCompleteAuthorizedUnits(
    _ expectations: [ExpectedKnowledge],
    in authorizedWindow: AuthorizedInferenceWindow
) -> Bool {
    let completeSupportSets = authorizedWindow.messageIDsByUnitIndex.values.map(Set.init)

    return expectations.allSatisfy { expectation in
        completeSupportSets.contains(expectation.supportingMessageIDs)
    }
}

func requireForbiddenEvidenceInWindow(
    _ forbiddenMessageIDs: Set<MessageID>, in authorizedWindow: AuthorizedInferenceWindow
) throws {
    guard forbiddenMessageIDs.isSubset(of: Set(authorizedWindow.fragmentsByMessageID.keys)) else {
        throw EvaluationFailure.forbiddenSupportUnavailableToInference
    }
}

private func loadTranscriptSource(for evaluationSession: EvaluationSession) throws -> Data {
    do {
        return try Data(contentsOf: URL(filePath: evaluationSession.transcriptPath))
    } catch {
        throw EvaluationFailure.unreadableTranscript
    }
}

private func parseTranscript(
    from transcriptSource: Data,
    describedBy evaluationSession: EvaluationSession
) throws -> AgentTranscript {
    guard let transcriptText = String(data: transcriptSource, encoding: .utf8) else {
        throw EvaluationFailure.unreadableTranscript
    }

    switch evaluationSession.provider {
    case .claude:
        let labelledMessageIDs = Set(
            evaluationSession.expectedKnowledge.flatMap(\.supportingMessageIDs)
        )
        .union(evaluationSession.forbiddenMessageIDs)
        let matchingTranscripts = ClaudeTranscriptReader().transcripts(
            inLineDelimitedJSON: transcriptText, forProject: ProjectID()
        ).filter { transcript in
            labelledMessageIDs.isSubset(of: Set(transcript.messages.map(\.id)))
        }

        guard matchingTranscripts.count == 1, let transcript = matchingTranscripts.first else {
            throw EvaluationFailure.ambiguousTranscript
        }

        return transcript
    case .codex:
        guard
            let transcript = CodexTranscriptReader().transcript(
                inLineDelimitedJSON: transcriptText, forProject: ProjectID())
        else { throw EvaluationFailure.unreadableTranscript }

        return transcript
    case .superpowers, .graphify:
        throw EvaluationFailure.unsupportedProvider
    }
}
