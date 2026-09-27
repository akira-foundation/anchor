import AnchorApplication
import AnchorDomain
import Foundation
import MCP

public struct ContextQueryActions: Sendable {
    public let currentProject: ResolveCurrentProjectAction
    public let resume: BuildProjectResumeAction
    public let search: SearchProjectContextAction
    public let listArtifacts: ListProjectArtifactsAction
    public let readArtifact: ReadProjectArtifactAction
    public let listSessions: ListProjectSessionsAction
    public let readSession: ReadProjectSessionAction
    public let readMessages: ReadSessionMessagesAction

    public init(
        currentProject: ResolveCurrentProjectAction, resume: BuildProjectResumeAction,
        search: SearchProjectContextAction, listArtifacts: ListProjectArtifactsAction,
        readArtifact: ReadProjectArtifactAction, listSessions: ListProjectSessionsAction,
        readSession: ReadProjectSessionAction, readMessages: ReadSessionMessagesAction
    ) {
        self.currentProject = currentProject
        self.resume = resume
        self.search = search
        self.listArtifacts = listArtifacts
        self.readArtifact = readArtifact
        self.listSessions = listSessions
        self.readSession = readSession
        self.readMessages = readMessages
    }
}

public struct AnchorMCPToolRouter: Sendable {
    private let actions: ContextQueryActions
    private let catalog = AnchorMCPToolCatalog()

    public init(actions: ContextQueryActions) { self.actions = actions }

    public func call(_ parameters: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = try validatedArguments(parameters)
        do {
            switch parameters.name {
            case "context.current_project":
                let project = try await actions.currentProject.perform(ProjectContextRequest())
                return response(
                    .object(projectFields(project)), summary: "Project context available.")
            case "context.resume":
                let resume = try await actions.resume.perform(ProjectContextRequest())
                return response(resumeFields(resume), summary: "Project resume available.")
            case "context.search":
                guard
                    let request = SearchProjectContextRequest(
                        text: try requiredString("text", arguments),
                        limit: try optionalInt("limit", arguments),
                        cursor: try optionalCursor("cursor", arguments))
                else { throw invalidParameters() }
                let page = try await actions.search.perform(request)
                return response(
                    pageFields(
                        page.records.map(searchFields), cursor: page.nextCursor, key: "hits"),
                    summary: "Found \(page.records.count) context hits.")
            case "context.list_artifacts":
                guard
                    let request = ListProjectArtifactsRequest(
                        provider: try optionalProvider(arguments),
                        limit: try optionalInt("limit", arguments),
                        cursor: try optionalCursor("cursor", arguments))
                else { throw invalidParameters() }
                let page = try await actions.listArtifacts.perform(request)
                return response(
                    pageFields(
                        page.records.map(artifactRecordFields), cursor: page.nextCursor,
                        key: "artifacts"), summary: "Listed \(page.records.count) artifacts.")
            case "context.get_artifact":
                guard
                    let artifactID = ArtifactID(
                        rawValue: try requiredString("artifact_id", arguments)),
                    let request = ReadProjectArtifactRequest(
                        artifactID: artifactID, revisionID: try optionalRevisionID(arguments),
                        cursor: try optionalCursor("content_cursor", arguments),
                        byteLimit: try optionalInt("byte_limit", arguments) ?? 16_384)
                else { throw invalidParameters() }
                let chunk = try await actions.readArtifact.perform(request)
                var fields = artifactFields(chunk.artifact)
                fields["revision_id"] = .string(chunk.revision.id.rawValue)
                fields["content_hash"] = .string(chunk.revision.contentHash.rawValue)
                fields["created_at"] = timestampValue(chunk.revision.createdAt)
                fields["text"] = .string(chunk.text)
                fields["is_truncated"] = .bool(chunk.isTruncated)
                if let cursor = chunk.nextCursor {
                    fields["next_cursor"] = .string(cursor.rawValue)
                }
                return response(.object(fields), summary: "Artifact text chunk available.")
            case "context.list_sessions":
                guard
                    let request = ListProjectSessionsRequest(
                        provider: try optionalProvider(arguments),
                        limit: try optionalInt("limit", arguments),
                        cursor: try optionalCursor("cursor", arguments))
                else { throw invalidParameters() }
                let page = try await actions.listSessions.perform(request)
                return response(
                    pageFields(
                        page.records.map(sessionRecordFields), cursor: page.nextCursor,
                        key: "sessions"), summary: "Listed \(page.records.count) sessions.")
            case "context.get_session":
                guard
                    let sessionID = SessionID(rawValue: try requiredString("session_id", arguments))
                else { throw invalidParameters() }
                let record = try await actions.readSession.perform(.init(sessionID: sessionID))
                return response(sessionRecordFields(record), summary: "Session metadata available.")
            case "context.get_messages":
                guard
                    let sessionID = SessionID(
                        rawValue: try requiredString("session_id", arguments)),
                    let request = ReadSessionMessagesRequest(
                        sessionID: sessionID, limit: try optionalInt("limit", arguments),
                        cursor: try optionalCursor("cursor", arguments))
                else { throw invalidParameters() }
                let page = try await actions.readMessages.perform(request)
                return response(
                    pageFields(
                        page.records.map(entryFields), cursor: page.nextCursor,
                        key: "entries"),
                    summary: "Listed \(page.records.count) conversation entries.")
            default:
                throw invalidParameters()
            }
        } catch let failure as ContextQueryFailure {
            return failureResponse(failure)
        } catch let failure as MCPError {
            throw failure
        } catch {
            return failureResponse(.readFailed)
        }
    }

    private func validatedArguments(_ parameters: CallTool.Parameters) throws -> [String: Value] {
        guard let tool = catalog.tools.first(where: { $0.name == parameters.name }),
            let schema = tool.inputSchema.objectValue,
            let properties = schema["properties"]?.objectValue
        else { throw invalidParameters() }
        let arguments = parameters.arguments ?? [:]
        guard Set(arguments.keys).isSubset(of: Set(properties.keys)),
            let required = schema["required"]?.arrayValue,
            required.allSatisfy({ $0.stringValue.map { arguments[$0] != nil } == true })
        else { throw invalidParameters() }
        for (name, argument) in arguments {
            guard let property = properties[name]?.objectValue,
                let type = property["type"]?.stringValue
            else { throw invalidParameters() }
            switch type {
            case "string":
                guard let string = argument.stringValue,
                    string.count >= (property["minLength"]?.intValue ?? 0),
                    property["enum"]?.arrayValue?.contains(.string(string)) ?? true
                else { throw invalidParameters() }
            case "integer":
                guard let integer = argument.intValue,
                    integer >= (property["minimum"]?.intValue ?? Int.min),
                    integer <= (property["maximum"]?.intValue ?? Int.max)
                else { throw invalidParameters() }
            default: throw invalidParameters()
            }
        }
        return arguments
    }

    private func requiredString(_ name: String, _ arguments: [String: Value]) throws -> String {
        guard let string = arguments[name]?.stringValue else { throw invalidParameters() }
        return string
    }

    private func optionalInt(_ name: String, _ arguments: [String: Value]) throws -> Int? {
        guard let argument = arguments[name] else { return nil }
        guard let integer = argument.intValue else { throw invalidParameters() }
        return integer
    }

    private func optionalCursor(
        _ name: String, _ arguments: [String: Value]
    ) throws -> ContextPageCursor? {
        guard let argument = arguments[name] else { return nil }
        guard let string = argument.stringValue, let cursor = ContextPageCursor(rawValue: string)
        else { throw invalidParameters() }
        return cursor
    }

    private func optionalRevisionID(_ arguments: [String: Value]) throws -> RevisionID? {
        guard let argument = arguments["revision_id"] else { return nil }
        guard let string = argument.stringValue, let identifier = RevisionID(rawValue: string)
        else { throw invalidParameters() }
        return identifier
    }

    private func optionalProvider(_ arguments: [String: Value]) throws -> AgentProvider? {
        guard let argument = arguments["provider"] else { return nil }
        guard let string = argument.stringValue, let provider = AgentProvider(rawValue: string)
        else { throw invalidParameters() }
        return provider
    }

    private func invalidParameters() -> MCPError {
        .invalidParams("Invalid tool name or arguments")
    }

    private func response(_ structured: Value, summary: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: summary, annotations: nil, _meta: nil)],
            structuredContent: Optional.some(structured), isError: false)
    }

    private func failureResponse(_ failure: ContextQueryFailure) -> CallTool.Result {
        let code: String
        switch failure {
        case .workspaceNotConfigured: code = "workspace_not_configured"
        case .workspaceNotAuthorized: code = "workspace_not_authorized"
        case .contextUnavailable: code = "context_unavailable"
        case .entityNotFound: code = "entity_not_found"
        case .invalidCursor: code = "invalid_cursor"
        case .contentIsNotText: code = "content_not_text"
        case .readFailed: code = "read_failed"
        }
        let message = "The context request could not be completed (\(code))."
        return CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            structuredContent: Optional.some(
                .object(["code": .string(code), "message": .string(message)])),
            isError: true)
    }

}
