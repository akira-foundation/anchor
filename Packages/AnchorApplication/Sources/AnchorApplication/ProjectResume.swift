import AnchorDomain
import Foundation

public struct ProjectResumeLimits: Sendable, Hashable {
    public static let compact = ProjectResumeLimits(
        maximumGraphCount: 3,
        maximumKnowledgeCountPerKind: 5,
        maximumSummaryByteCount: 512
    )

    public let maximumGraphCount: Int
    public let maximumKnowledgeCountPerKind: Int
    public let maximumSummaryByteCount: Int

    public init(
        maximumGraphCount: Int,
        maximumKnowledgeCountPerKind: Int,
        maximumSummaryByteCount: Int
    ) {
        self.maximumGraphCount = maximumGraphCount
        self.maximumKnowledgeCountPerKind = maximumKnowledgeCountPerKind
        self.maximumSummaryByteCount = maximumSummaryByteCount
    }
}

public struct ProjectResumeKnowledgeEntry: Sendable, Hashable {
    public let id: KnowledgeEntryID
    public let kind: KnowledgeEntryKind
    public let summary: String
    public let source: KnowledgeEntrySource
    public let origin: KnowledgeEntryOrigin
    public let createdAt: Date
    public let summaryIsTruncated: Bool

    public init(compacting entry: KnowledgeEntry, maximumSummaryByteCount: Int) {
        id = entry.id
        kind = entry.kind
        source = entry.source
        origin = entry.origin
        createdAt = entry.createdAt

        let compacted = Self.compact(
            entry.summaryText, maximumByteCount: maximumSummaryByteCount)
        summary = compacted.text
        summaryIsTruncated = compacted.isTruncated
    }

    private static func compact(
        _ text: String, maximumByteCount: Int
    ) -> (text: String, isTruncated: Bool) {
        guard text.utf8.count > maximumByteCount else { return (text, false) }

        let marker = "… [truncated]"
        let prefixByteLimit = max(0, maximumByteCount - marker.utf8.count)
        var prefix = ""
        var prefixByteCount = 0
        for scalar in text.unicodeScalars {
            let scalarText = String(scalar)
            let scalarByteCount = scalarText.utf8.count
            guard prefixByteCount + scalarByteCount <= prefixByteLimit else { break }
            prefix.unicodeScalars.append(scalar)
            prefixByteCount += scalarByteCount
        }
        return (prefix + marker, true)
    }
}

public struct ProjectResume: Sendable, Hashable {
    public let project: ProjectContext
    public let recentSession: SessionContextRecord?
    public let lastPresence: DevicePresence?
    public let latestArtifactRevisionAt: Date?
    public let latestKnowledgeEntryAt: Date?
    public let currentPlan: ArtifactContextRecord?
    public let latestBrainstorm: ArtifactContextRecord?
    public let relevantGraphs: [ArtifactContextRecord]
    public let recentDecisions: [ProjectResumeKnowledgeEntry]
    public let openTodos: [ProjectResumeKnowledgeEntry]
    public let openQuestions: [ProjectResumeKnowledgeEntry]
    public let hasMoreDecisions: Bool
    public let hasMoreTodos: Bool
    public let hasMoreQuestions: Bool

    public var lastActivityAt: Date? {
        [
            recentSession?.session.updatedAt,
            lastPresence?.lastSeenAt,
            latestArtifactRevisionAt,
            latestKnowledgeEntryAt,
        ].compactMap { $0 }.max()
    }

    public var lastAgentProvider: AgentProvider? { recentSession?.session.provider }

    public init(
        project: ProjectContext,
        recentSession: SessionContextRecord? = nil,
        lastPresence: DevicePresence? = nil,
        latestArtifactRevisionAt: Date? = nil,
        latestKnowledgeEntryAt: Date? = nil,
        currentPlan: ArtifactContextRecord? = nil,
        latestBrainstorm: ArtifactContextRecord? = nil,
        relevantGraphs: [ArtifactContextRecord] = [],
        recentDecisions: [ProjectResumeKnowledgeEntry] = [],
        openTodos: [ProjectResumeKnowledgeEntry] = [],
        openQuestions: [ProjectResumeKnowledgeEntry] = [],
        hasMoreDecisions: Bool = false,
        hasMoreTodos: Bool = false,
        hasMoreQuestions: Bool = false
    ) {
        self.project = project
        self.recentSession = recentSession
        self.lastPresence = lastPresence
        self.latestArtifactRevisionAt = latestArtifactRevisionAt
        self.latestKnowledgeEntryAt = latestKnowledgeEntryAt
        self.currentPlan = currentPlan
        self.latestBrainstorm = latestBrainstorm
        self.relevantGraphs = relevantGraphs
        self.recentDecisions = recentDecisions
        self.openTodos = openTodos
        self.openQuestions = openQuestions
        self.hasMoreDecisions = hasMoreDecisions
        self.hasMoreTodos = hasMoreTodos
        self.hasMoreQuestions = hasMoreQuestions
    }
}
