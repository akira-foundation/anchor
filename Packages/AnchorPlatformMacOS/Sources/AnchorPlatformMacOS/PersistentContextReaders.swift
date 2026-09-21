import AnchorApplication
import AnchorDomain
import AnchorPersistence
import AnchorSearch
import Foundation

actor PersistentContextReaders: ProjectContextReading, ArtifactContextReading,
    SessionContextReading, ProjectContextSearching, ProjectConversationReading
{
    private let databaseURL: URL
    private let status: ContextReadModelStatusStore
    private var database: SQLiteDatabase?

    init(databaseURL: URL, status: ContextReadModelStatusStore) {
        self.databaseURL = databaseURL
        self.status = status
    }

    func loadProjectContext(forWorkspaceAt workspaceURL: URL) async throws -> ProjectContext? {
        try await read { artifacts, _ in
            try await artifacts.loadProjectContext(forWorkspaceAt: workspaceURL)
        }
    }
    func listArtifacts(
        forProject projectID: ProjectID, provider: AgentProvider?, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<ArtifactContextRecord>
    {
        try await read { artifacts, _ in
            try await artifacts.listArtifacts(
                forProject: projectID, provider: provider, page: page,
                binding: binding)
        }
    }
    func loadArtifact(withIdentifier artifactID: ArtifactID) async throws -> ArtifactContextRecord?
    {
        try await read { artifacts, _ in
            try await artifacts.loadArtifact(withIdentifier: artifactID)
        }
    }
    func listSessions(
        forProject projectID: ProjectID, provider: AgentProvider?, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<SessionContextRecord>
    {
        try await read { _, sessions in
            try await sessions.listSessions(
                forProject: projectID, provider: provider, page: page,
                binding: binding)
        }
    }
    func loadSession(withIdentifier sessionID: SessionID) async throws -> SessionContextRecord? {
        try await read { _, sessions in try await sessions.loadSession(withIdentifier: sessionID) }
    }
    func loadConversationEntries(
        inSession sessionID: SessionID, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<ConversationEntry>
    {
        try await read { _, sessions in
            try await sessions.loadConversationEntries(
                inSession: sessionID, page: page,
                binding: binding)
        }
    }
    func searchContext(
        forProject projectID: ProjectID, matching text: String, page: ContextPageRequest,
        binding: ContextCursorBinding
    )
        async throws -> ContextPage<ProjectContextSearchHit>
    {
        try await read { _, search in
            try await search.searchContext(
                forProject: projectID, matching: text, page: page,
                binding: binding)
        }
    }

    func loadConversationEntries(
        inSession sessionID: SessionID, forProject projectID: ProjectID,
        page: ContextPageRequest, binding: ContextCursorBinding
    ) async throws -> ContextPage<ConversationEntry> {
        try await read { _, sessions in
            try await sessions.loadConversationEntries(
                inSession: sessionID, forProject: projectID, page: page, binding: binding)
        }
    }

    private func read<Output: Sendable>(
        _ operation: (SQLiteArtifactContextStore, SQLiteContextSearch) async throws -> Output
    ) async throws -> Output {
        try await status.requireAvailable()
        guard FileManager.default.fileExists(atPath: databaseURL.path(percentEncoded: false)) else {
            throw ContextQueryFailure.contextUnavailable
        }
        let connection: SQLiteDatabase
        if let database {
            connection = database
        } else {
            do { connection = try SQLiteDatabase(fileURL: databaseURL, readOnly: true) } catch {
                throw ContextQueryFailure.contextUnavailable
            }
            database = connection
        }
        let output = try await operation(
            SQLiteArtifactContextStore(existingDatabase: connection),
            SQLiteContextSearch(existingDatabase: connection))
        try await status.requireAvailable()
        return output
    }
}
