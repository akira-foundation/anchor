import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import AnchorProvider
import AnchorSearch
import AnchorStorage
import CryptoKit
import Foundation

@testable import AnchorPlatformMacOS

struct ContextAssemblyFixture {
    let root: URL
    let support: URL
    let configurationURL: URL
    let observed: ObservedWorkspace
    let key = SymmetricKey(size: .bits256)
    let keyLoads = KeyLoadCount()
    let transcript: AgentTranscript

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "anchor-context-\(UUID().uuidString)")
        support = root.appending(path: "support")
        configurationURL = support.appending(path: "configured.json")
        let workspace = root.appending(path: "workspace")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        observed = ObservedWorkspace(workspaceURL: workspace, projectName: "assembly-fixture")
        try JSONSerialization.data(withJSONObject: [
            "workspacePath": workspace.path(), "projectName": observed.projectName,
        ])
        .write(to: configurationURL)
        let sessionID = SessionID.derived(fromSeed: "assembly-session")
        transcript = AgentTranscript(
            session: AgentSession(
                id: sessionID, projectID: observed.projectID,
                provider: .claude, startedAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)),
            entries: [
                .message(
                    ConversationMessage(
                        id: MessageID.derived(fromSeed: "assembly-message"), sessionID: sessionID,
                        role: .user, content: "checkpoint ready",
                        timestamp: Date(timeIntervalSince1970: 20)))
            ])
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
    func writer() async throws -> ContextReadModelWriter {
        try await ContextReadModelAssembly.openWriter(
            supportDirectoryURL: support,
            configurationURL: configurationURL, remoteReader: NoRepositoryRemote())
    }
    func reader(
        requestedPath: String? = nil, key: SymmetricKey? = nil
    ) async throws -> ContextReadModelReader {
        try await ContextReadModelAssembly.openReader(
            requestedWorkspacePath: requestedPath ?? observed.workspaceURL.path(),
            supportDirectoryURL: support, configurationURL: configurationURL,
            keyLoader: {
                await keyLoads.record()
                return key
            })
    }
    func storage() async -> AssembledContextStorage {
        await ContextStorageAssembly.assemble(
            reachingRemote: { nil }, localRootURL: support.appending(path: "storage"), key: key)
    }
    func rebuilder(
        writer: ContextReadModelWriter, storage: AssembledContextStorage,
        failing: Bool = false,
        presenceRemote: any DevicePresenceRegistry = DeferredDevicePresenceRegistry()
    ) async throws -> ContextReadModelRebuilder {
        let contentStore = StoredArtifactContentStore(storage: storage.local)
        _ = try await SQLiteKnowledgeStore(database: writer.database)
        return ContextReadModelRebuilder(
            projectID: observed.projectID,
            discoverer: SuperpowersArtifactProvider(workspaceURL: observed.workspaceURL),
            journal: StoredArtifactRevisionJournal(
                storage: storage.local, contentStore: contentStore),
            artifacts: writer.artifacts,
            transcripts: failing
                ? RefusingTranscriptReplacement()
                : try await SQLiteContextSearch(database: writer.database),
            canonicalSessions: { [transcript, observed] in
                guard
                    let session = SessionArtifact.make(
                        from: transcript, forProject: observed.projectID)
                else { return [] }
                return [session]
            },
            presences: ReadModelDevicePresenceRegistry(
                snapshot: writer.presences, remote: presenceRemote),
            status: writer.status)
    }
    func seed() async throws -> RecordedArtifactRevision {
        let planURL = observed.workspaceURL.appending(path: "docs/superpowers/plans/current.md")
        try FileManager.default.createDirectory(
            at: planURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = Data("unchanged plan".utf8)
        try content.write(to: planURL)
        let discoveries = try await SuperpowersArtifactProvider(workspaceURL: observed.workspaceURL)
            .discoverArtifacts(forProject: observed.projectID)
        let artifact = discoveries[0].artifact
        let revision = ArtifactRevision(
            id: RevisionID(), artifactID: artifact.id, parentRevisionID: nil,
            contentHash: ContentHash.digest(of: content), deviceID: DeviceID(),
            createdAt: Date(timeIntervalSince1970: 123.125))!
        let storage = await storage()
        let contents = StoredArtifactContentStore(storage: storage.local)
        try await contents.storeContent(content, forRevision: revision.id)
        try await StoredArtifactRevisionJournal(storage: storage.local, contentStore: contents)
            .recordRevision(revision)
        let writer = try await writer()
        let rebuilder = try await rebuilder(writer: writer, storage: storage)
        _ = try await rebuilder.rebuild()
        _ = try await rebuilder.rebuild()
        return RecordedArtifactRevision(artifact: artifact, revision: revision)
    }
}

struct NoRepositoryRemote: RepositoryRemoteReading {
    func readRepositoryRemote(atDirectory directoryURL: URL) async throws -> RepositoryRemoteOutcome
    { .repositoryWithoutRemote }
}

actor KeyLoadCount {
    var count = 0
    func record() { count += 1 }
}

struct RefusingTranscriptReplacement: ProjectTranscriptsReplacing {
    enum Failure: Error { case refused }
    func replaceTranscripts(
        _ transcripts: [AgentTranscript], forProject projectID: ProjectID
    ) async throws { throw Failure.refused }
}
