import AnchorDomain
import Foundation

public struct PublishProjectContextRequest: Sendable {
    public let workspaceURL: URL

    public init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
    }
}

public struct PublishProjectContextReport: Sendable, Equatable {
    public let refusals: [String]
}

public struct PublishProjectContextAction: Action {
    private let reader: any PublishableProjectContextReading
    private let projects: any ProjectDescriptorPublishing
    private let artifacts: any ArtifactDescriptorPublishing
    private let knowledge: any KnowledgeSnapshotPublishing

    public init(
        reader: any PublishableProjectContextReading,
        projects: any ProjectDescriptorPublishing,
        artifacts: any ArtifactDescriptorPublishing,
        knowledge: any KnowledgeSnapshotPublishing
    ) {
        self.reader = reader
        self.projects = projects
        self.artifacts = artifacts
        self.knowledge = knowledge
    }

    public func perform(
        _ request: PublishProjectContextRequest
    ) async throws -> PublishProjectContextReport {
        guard
            let context = try await reader.loadPublishableProjectContext(
                forWorkspaceAt: request.workspaceURL)
        else { return PublishProjectContextReport(refusals: []) }

        var refusals: [String] = []
        if let refusal = try await refusal(
            publishing: "project \(context.project.displayName)",
            {
                try await projects.publishProjectDescriptor(context.project)
            })
        {
            refusals.append(refusal)
        }
        for artifact in context.artifacts {
            if let refusal = try await refusal(
                publishing: "artifact \(artifact.name)",
                {
                    try await artifacts.publishArtifactDescriptor(artifact)
                })
            {
                refusals.append(refusal)
            }
        }
        for snapshot in Self.knowledgeSnapshots(in: context) {
            if let refusal = try await refusal(
                publishing: "knowledge \(snapshot.source)",
                {
                    try await knowledge.publishKnowledgeSnapshot(snapshot)
                })
            {
                refusals.append(refusal)
            }
        }

        return PublishProjectContextReport(refusals: refusals)
    }

    private func refusal(
        publishing target: String, _ publication: () async throws -> Void
    ) async throws -> String? {
        try Task.checkCancellation()
        do {
            try await publication()
            return nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return "publishing \(target): \(error)"
        }
    }

    private static func knowledgeSnapshots(
        in context: PublishableProjectContext
    ) -> [KnowledgeSourceSnapshot] {
        let projectID = context.project.projectID
        var orderedSources: [KnowledgeEntrySource] = []
        var seenSources: Set<KnowledgeEntrySource> = []
        for entry in context.knowledgeEntries where entry.projectID == projectID {
            guard seenSources.insert(entry.source).inserted else { continue }
            orderedSources.append(entry.source)
        }

        return orderedSources.compactMap { source in
            KnowledgeSourceSnapshot(
                projectID: projectID,
                source: source,
                entries: context.knowledgeEntries.filter {
                    $0.projectID == projectID && $0.source == source && $0.state == .current
                })
        }
    }
}
