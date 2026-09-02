import AnchorApplication
import AnchorDomain
import AnchorKnowledge
import AnchorPersistence
import AnchorSearch
import AnchorStorage
import AnchorSync
import Foundation

public enum ContextEngineAssembly {
    public static func makeCoordinator(
        device: Device,
        observedWorkspace: ObservedWorkspace,
        storage: AssembledContextStorage,
        supportDirectoryURL: URL,
        sessionFileIndex: SessionFileIndex? = nil,
        sessionContext: SessionContextRecording? = nil
    ) -> WorkspaceObservationCoordinator {
        let workspaceURL = observedWorkspace.workspaceURL
        let projectID = observedWorkspace.projectID
        let operationJournal = StoredSyncOperationJournal(storage: storage.local)

        return WorkspaceObservationCoordinator(
            device: device,
            observer: FileSystemEventObserver(),
            checkpointStore: ObservationCheckpointStore(
                fileURL: checkpointFileURL(forProject: projectID, in: supportDirectoryURL)),
            operationJournal: operationJournal,
            recordChange: RecordWorkspaceChangeAction(
                discoverer: makeDiscoverer(
                    workspaceURL: workspaceURL, sessionFileIndex: sessionFileIndex),
                contentReader: makeContentReader(projectID: projectID),
                revisionRecorder: ArtifactRevisionRecorder(
                    journal: makeRevisionJournal(over: storage.local),
                    contentStore: StoredArtifactContentStore(storage: storage.local),
                    deviceID: device.id
                ),
                operationJournal: operationJournal
            ),
            synchronizer: makeSynchronizer(storage: storage, operations: operationJournal),
            presences: makePresences(storage: storage),
            sessionContext: sessionContext
        )
    }

    public static func makeSessionFileIndex(
        inSupportDirectoryAt supportDirectoryURL: URL
    ) async -> SessionFileIndex? {
        try? FileManager.default.createDirectory(
            at: supportDirectoryURL, withIntermediateDirectories: true)

        guard
            let database = try? SQLiteDatabase(
                fileURL: supportDirectoryURL.appending(path: "sessions.sqlite"))
        else { return nil }

        return try? await SessionFileIndex(database: database)
    }

    public static func makeSessionContext(
        storage: AssembledContextStorage
    ) async throws -> AssembledSessionContext {
        let database = try SQLiteDatabase(fileURL: nil)
        let search = try await SQLiteContextSearch(database: database)
        let action = RecordSessionContextAction(
            index: SearchedTranscriptIndex(search: search),
            knowledge: ExtractedSessionKnowledge(
                extractor: MarkedKnowledgeExtractor(),
                store: try await SQLiteKnowledgeStore(database: database)
            )
        )

        return AssembledSessionContext(
            search: search,
            recorder: StoredSessionContextRecorder(
                contentStore: StoredArtifactContentStore(storage: storage.local), action: action),
            rebuilder: DiscoveredSessionContextRebuilder(action: action)
        )
    }

    public static func sessionsOnDisk(
        forProject projectID: ProjectID,
        inWorkspaceAt workspaceURL: URL,
        sessionFileIndex: SessionFileIndex? = nil
    ) -> [(artifact: Artifact, content: Data)] {
        claudeSessions().sessionArtifacts(forProject: projectID, inWorkspaceAt: workspaceURL)
            + codexSessions(indexedBy: sessionFileIndex)
            .sessionArtifacts(forProject: projectID, inWorkspaceAt: workspaceURL)
    }

    private static func claudeSessions() -> ClaudeSessionArtifacts {
        ClaudeSessionArtifacts()
    }

    private static func codexSessions(
        indexedBy sessionFileIndex: SessionFileIndex?
    ) -> CodexSessionArtifacts {
        CodexSessionArtifacts(index: sessionFileIndex)
    }

    private static func makeDiscoverer(
        workspaceURL: URL, sessionFileIndex: SessionFileIndex?
    ) -> CompositeArtifactDiscoverer {
        CompositeArtifactDiscoverer([
            SuperpowersArtifactProvider(workspaceURL: workspaceURL),
            GraphifyArtifactProvider(workspaceURL: workspaceURL),
            ClaudeSessionProvider(workspaceURL: workspaceURL, artifacts: claudeSessions()),
            CodexSessionProvider(
                workspaceURL: workspaceURL,
                artifacts: codexSessions(indexedBy: sessionFileIndex)
            ),
        ])
    }

    private static func makeContentReader(
        projectID: ProjectID
    ) -> CompositeArtifactContentReader {
        CompositeArtifactContentReader([
            WorkspaceFileContentReader(),
            ClaudeSessionContentReader(projectID: projectID),
            CodexSessionContentReader(projectID: projectID),
        ])
    }

    private static func makeSynchronizer(
        storage: AssembledContextStorage, operations: StoredSyncOperationJournal
    ) -> any ArtifactRevisionSynchronizing {
        guard let remote = storage.remote else { return DeferredArtifactSynchronizer() }

        return ArtifactSynchronizer(
            local: makeRevisionStore(over: storage.local),
            remote: makeRevisionStore(over: remote),
            operations: operations,
            failures: StorageFailureClassifier(),
            feed: StoredRevisionFeed(storage: remote),
            cursors: StoredSyncCursorStore(storage: storage.local),
            divergences: StoredArtifactDivergenceJournal(storage: storage.local)
        )
    }

    private static func makePresences(
        storage: AssembledContextStorage
    ) -> any DevicePresenceRegistry {
        guard let remote = storage.remote else { return DeferredDevicePresenceRegistry() }

        return StoredDevicePresenceRegistry(storage: remote)
    }

    private static func makeRevisionStore(over storage: any StorageProvider) -> RevisionStore {
        RevisionStore(
            journal: makeRevisionJournal(over: storage),
            contents: StoredArtifactContentStore(storage: storage)
        )
    }

    private static func makeRevisionJournal(
        over storage: any StorageProvider
    ) -> StoredArtifactRevisionJournal {
        StoredArtifactRevisionJournal(
            storage: storage, contentStore: StoredArtifactContentStore(storage: storage))
    }

    private static func checkpointFileURL(
        forProject projectID: ProjectID, in supportDirectoryURL: URL
    ) -> URL {
        supportDirectoryURL
            .appending(path: "checkpoints")
            .appending(path: "\(projectID.rawValue).json")
    }
}
