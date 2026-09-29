import AnchorApplication
import AnchorDomain
import AnchorPersistence
import CryptoKit
import Foundation

public struct ContextReadModelWriter: Sendable {
    public let databaseURL: URL
    public let database: SQLiteDatabase
    public let status: ContextReadModelStatusStore
    public let artifacts: SQLiteArtifactContextStore
    public let presences: SQLiteDevicePresenceSnapshotStore
    public let observedWorkspace: ObservedWorkspace
}

public struct ContextReadModelReader: Sendable {
    public let databaseURL: URL
    public let currentProject: ResolveCurrentProjectAction
    public let resume: BuildProjectResumeAction
    public let search: SearchProjectContextAction
    public let listArtifacts: ListProjectArtifactsAction
    public let readArtifact: ReadProjectArtifactAction
    public let listSessions: ListProjectSessionsAction
    public let readSession: ReadProjectSessionAction
    public let readMessages: ReadSessionMessagesAction
    public let listKnowledge: ListProjectKnowledgeAction
    public let readKnowledge: ReadProjectKnowledgeAction
}

public enum ContextReadModelAssembly {
    public static func openWriter(
        supportDirectoryURL: URL, configurationURL: URL,
        remoteReader: any RepositoryRemoteReading
    ) async throws -> ContextReadModelWriter {
        guard
            let observed = try ObservedWorkspaceConfiguration(fileURL: configurationURL)
                .observedWorkspace()
        else {
            throw ContextQueryFailure.workspaceNotConfigured
        }
        let location = ContextReadModelLocation(supportDirectoryURL: supportDirectoryURL)
        let status = ContextReadModelStatusStore(supportDirectoryURL: supportDirectoryURL)
        try await status.markRebuildRequired()
        let database = try SQLiteDatabase(fileURL: location.databaseURL)
        let artifacts = try await SQLiteArtifactContextStore(database: database)
        let presences = try await SQLiteDevicePresenceSnapshotStore(database: database)
        let remoteOutcome = try await remoteReader.readRepositoryRemote(
            atDirectory: observed.workspaceURL)
        let remote: CanonicalRepositoryRemote?
        if case .remote(let canonicalRemote) = remoteOutcome {
            remote = canonicalRemote
        } else {
            remote = nil
        }
        try await artifacts.recordProjectContext(
            ProjectContext(
                projectID: observed.projectID,
                displayName: observed.projectName, canonicalRepositoryRemote: remote,
                workspaceURL: observed.workspaceURL))
        return ContextReadModelWriter(
            databaseURL: location.databaseURL, database: database, status: status,
            artifacts: artifacts, presences: presences, observedWorkspace: observed)
    }

    public static func openReader(
        requestedWorkspacePath: String, supportDirectoryURL: URL,
        configurationURL: URL, keyLoader: @escaping @Sendable () async throws -> SymmetricKey?
    ) async throws -> ContextReadModelReader {
        let location = ContextReadModelLocation(supportDirectoryURL: supportDirectoryURL)
        let status = ContextReadModelStatusStore(supportDirectoryURL: supportDirectoryURL)
        let readers = PersistentContextReaders(
            databaseURL: location.databaseURL,
            status: status)
        let workspace = try AuthorizedWorkspaceContextReader(
            requestedWorkspacePath: requestedWorkspacePath,
            configurationURL: configurationURL, projects: readers)
        let content = StoredArtifactContextReader(
            storageURL: supportDirectoryURL.appending(path: "storage"), keyLoader: keyLoader)
        return ContextReadModelReader(
            databaseURL: location.databaseURL,
            currentProject: ResolveCurrentProjectAction(workspace: workspace, availability: status),
            resume: BuildProjectResumeAction(
                workspace: workspace, resumes: readers, availability: status),
            search: SearchProjectContextAction(
                workspace: workspace, search: readers, availability: status),
            listArtifacts: ListProjectArtifactsAction(
                workspace: workspace, artifacts: readers, availability: status),
            readArtifact: ReadProjectArtifactAction(
                workspace: workspace, artifacts: readers, content: content, availability: status),
            listSessions: ListProjectSessionsAction(
                workspace: workspace, sessions: readers, availability: status),
            readSession: ReadProjectSessionAction(
                workspace: workspace, sessions: readers, availability: status),
            readMessages: ReadSessionMessagesAction(
                workspace: workspace, entries: readers, availability: status),
            listKnowledge: ListProjectKnowledgeAction(
                workspace: workspace, knowledge: readers, availability: status),
            readKnowledge: ReadProjectKnowledgeAction(
                workspace: workspace, knowledge: readers, availability: status))
    }
}
