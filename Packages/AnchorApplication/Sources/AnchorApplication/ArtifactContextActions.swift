import AnchorDomain
import Foundation

public protocol ArtifactRevisionContentReading: Sendable {
    func loadRevision(withIdentifier revisionID: RevisionID) async throws -> ArtifactRevision?
    func readContent(forRevision revisionID: RevisionID) async throws -> Data?
}

public struct ListProjectArtifactsRequest: Sendable {
    public let provider: AgentProvider?
    public let page: ContextPageRequest

    public init?(
        provider: AgentProvider? = nil, limit: Int? = nil, cursor: ContextPageCursor? = nil
    ) {
        guard let page = ContextPageRequest(limit: limit, cursor: cursor, maximumLimit: 100) else {
            return nil
        }
        self.provider = provider
        self.page = page
    }
}

public struct ReadProjectArtifactRequest: Sendable {
    public let artifactID: ArtifactID
    public let revisionID: RevisionID?
    public let cursor: ContextPageCursor?
    public let byteLimit: Int

    public init?(
        artifactID: ArtifactID, revisionID: RevisionID? = nil,
        cursor: ContextPageCursor? = nil, byteLimit: Int = 16_384
    ) {
        guard (4...65_536).contains(byteLimit) else { return nil }
        self.artifactID = artifactID
        self.revisionID = revisionID
        self.cursor = cursor
        self.byteLimit = byteLimit
    }
}

public struct ArtifactContextChunk: Sendable, Hashable {
    public let artifact: Artifact
    public let revision: ArtifactRevision
    public let text: String
    public let nextCursor: ContextPageCursor?
    public var isTruncated: Bool { nextCursor != nil }
}

public struct ListProjectArtifactsAction: Action {
    private let availability: any ContextAvailabilityReading
    private let workspace: any AuthorizedProjectContextReading
    private let artifacts: any ArtifactContextReading

    public init(
        workspace: any AuthorizedProjectContextReading, artifacts: any ArtifactContextReading,
        availability: any ContextAvailabilityReading
    ) {
        self.availability = availability
        self.workspace = workspace
        self.artifacts = artifacts
    }

    public func perform(
        _ request: ListProjectArtifactsRequest
    ) async throws -> ContextPage<ArtifactContextRecord> {
        try await queryContext(availability: availability) { generation in
            let project = try await workspace.loadAuthorizedProjectContext()
            return try await artifacts.listArtifacts(
                forProject: project.projectID, provider: request.provider, page: request.page,
                binding: ContextCursorBinding(
                    workspaceURL: project.workspaceURL, generation: generation))
        }
    }
}

public struct ReadProjectArtifactAction: Action {
    private let availability: any ContextAvailabilityReading
    private let workspace: any AuthorizedProjectContextReading
    private let artifacts: any ArtifactContextReading
    private let content: any ArtifactRevisionContentReading

    public init(
        workspace: any AuthorizedProjectContextReading, artifacts: any ArtifactContextReading,
        content: any ArtifactRevisionContentReading, availability: any ContextAvailabilityReading
    ) {
        self.availability = availability
        self.workspace = workspace
        self.artifacts = artifacts
        self.content = content
    }

    public func perform(_ request: ReadProjectArtifactRequest) async throws -> ArtifactContextChunk
    {
        try await queryContext(availability: availability) { generation in
            let project = try await workspace.loadAuthorizedProjectContext()
            let binding = ContextCursorBinding(
                workspaceURL: project.workspaceURL, generation: generation)
            guard let record = try await artifacts.loadArtifact(withIdentifier: request.artifactID),
                record.artifact.projectID == project.projectID
            else { throw ContextQueryFailure.entityNotFound }
            let revision: ArtifactRevision?
            if let requestedRevision = request.revisionID {
                revision = try await content.loadRevision(withIdentifier: requestedRevision)
            } else {
                revision = record.latestRevision
            }
            guard let revision, revision.artifactID == record.artifact.id,
                request.revisionID == nil || revision.id == request.revisionID
            else { throw ContextQueryFailure.entityNotFound }
            let offset = try ArtifactChunkCursor.offset(
                request.cursor, project: project.projectID,
                artifact: record.artifact.id, revision: revision.id, binding: binding)
            guard let bytes = try await content.readContent(forRevision: revision.id) else {
                throw ContextQueryFailure.entityNotFound
            }
            guard String(data: bytes, encoding: .utf8) != nil else {
                throw ContextQueryFailure.contentIsNotText
            }
            guard offset <= bytes.count else { throw ContextQueryFailure.invalidCursor }
            let start = bytes.startIndex + offset
            guard offset == bytes.count || bytes[start] & 0xc0 != 0x80 else {
                throw ContextQueryFailure.invalidCursor
            }
            var end = start + min(request.byteLimit, bytes.count - offset)
            while end < bytes.endIndex, bytes[end] & 0xc0 == 0x80 { end -= 1 }
            let nextCursor =
                try end < bytes.endIndex
                ? ArtifactChunkCursor.encode(
                    offset: end - bytes.startIndex,
                    project: project.projectID, artifact: record.artifact.id, revision: revision.id,
                    binding: binding)
                : nil
            return ArtifactContextChunk(
                artifact: record.artifact, revision: revision,
                text: String(decoding: bytes[start..<end], as: UTF8.self), nextCursor: nextCursor)
        }
    }
}
