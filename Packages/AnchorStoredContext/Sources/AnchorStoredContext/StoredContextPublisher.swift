import AnchorApplication
import AnchorDomain
import AnchorStorage
import Foundation

public enum StoredContextPublicationFailure: Error, Sendable, Equatable {
    case unrepresentableKey
    case artifactIdentityMismatch(ArtifactID)
}

public struct StoredContextPublisher:
    ProjectDescriptorPublishing, ArtifactDescriptorPublishing, KnowledgeSnapshotPublishing
{
    private static let ledgerPrefix = "publication-ledger"

    private let remote: any StorageProvider
    private let ledger: any StorageProvider

    public init(remote: any StorageProvider, ledger: any StorageProvider) {
        self.remote = remote
        self.ledger = ledger
    }

    public func publishProjectDescriptor(_ descriptor: PublishedProjectDescriptor) async throws {
        try await publish(
            descriptor, at: PublishedContextKeys.projectKey(for: descriptor.projectID),
            precondition: .none)
    }

    public func publishArtifactDescriptor(_ artifact: Artifact) async throws {
        let derivedID = ArtifactID.derived(
            projectID: artifact.projectID, provider: artifact.provider, name: artifact.name)
        guard derivedID == artifact.id else {
            throw StoredContextPublicationFailure.artifactIdentityMismatch(artifact.id)
        }

        try await publish(
            PublishedArtifactDescriptor(artifact: artifact),
            at: PublishedContextKeys.artifactKey(for: artifact.id),
            precondition: .objectIsAbsent)
    }

    public func publishKnowledgeSnapshot(_ snapshot: KnowledgeSourceSnapshot) async throws {
        try await publish(
            snapshot,
            at: try PublishedContextKeys.knowledgeKey(
                for: snapshot.projectID, source: snapshot.source),
            precondition: .none)
    }

    private func publish<Body: Encodable>(
        _ body: Body, at remoteKey: StorageKey?, precondition: StorageWritePrecondition
    ) async throws {
        guard let remoteKey, let ledgerKey = ledgerKey(for: remoteKey) else {
            throw StoredContextPublicationFailure.unrepresentableKey
        }
        let contents = try PublishedContextCodec.encode(body)
        let publishedDigest = Data(ContentHash.digest(of: contents).rawValue.utf8)
        if let recorded = try await ledger.object(for: ledgerKey),
            recorded.object.contents == publishedDigest
        {
            return
        }

        do {
            try await remote.putObject(
                StorageObject(key: remoteKey, contents: contents), precondition: precondition)
        } catch .preconditionFailed where precondition == .objectIsAbsent {
        }

        try await ledger.putObject(
            StorageObject(key: ledgerKey, contents: publishedDigest), precondition: .none)
    }

    private func ledgerKey(for remoteKey: StorageKey) -> StorageKey? {
        StorageKey(
            rawValue:
                "\(Self.ledgerPrefix)/\(ContentHash.digest(of: Data(remoteKey.rawValue.utf8)).rawValue)"
        )
    }
}
