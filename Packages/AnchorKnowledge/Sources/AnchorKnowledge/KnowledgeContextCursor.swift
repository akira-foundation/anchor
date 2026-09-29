import AnchorApplication
import AnchorDomain
import Foundation

enum KnowledgeContextCursor {
    private static let version = 2

    static func encode(
        after entry: KnowledgeEntry?, projectID: ProjectID,
        kind: KnowledgeEntryKind?, origin: KnowledgeEntryOrigin?,
        binding: ContextCursorBinding
    ) throws -> ContextPageCursor? {
        guard let entry else { return nil }
        let cursorPayload = Payload(
            version: version, operation: "list-knowledge",
            workspacePath: binding.workspacePath,
            generation: binding.generation.identifier,
            projectID: projectID.rawValue,
            kindBinding: kind?.rawValue ?? "",
            originBinding: origin?.rawValue ?? "",
            createdAt: Int64(entry.createdAt.timeIntervalSince1970),
            knowledgeEntryID: entry.id.rawValue)
        let token = try JSONEncoder().encode(cursorPayload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard let cursor = ContextPageCursor(rawValue: token) else {
            throw ContextCursorFailure.invalid
        }
        return cursor
    }

    static func decode(
        _ cursor: ContextPageCursor?, projectID: ProjectID,
        kind: KnowledgeEntryKind?, origin: KnowledgeEntryOrigin?,
        binding: ContextCursorBinding
    ) throws -> Position? {
        guard let cursor else { return nil }
        guard cursor.rawValue.allSatisfy(Self.isURLSafeBase64Character) else {
            throw ContextCursorFailure.invalid
        }
        var encodedPayload = cursor.rawValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encodedPayload.append(String(repeating: "=", count: (4 - encodedPayload.count % 4) % 4))
        guard let payloadBytes = Data(base64Encoded: encodedPayload),
            let cursorPayload = try? JSONDecoder().decode(Payload.self, from: payloadBytes),
            cursorPayload.version == version,
            cursorPayload.operation == "list-knowledge",
            cursorPayload.workspacePath == binding.workspacePath,
            cursorPayload.generation == binding.generation.identifier,
            cursorPayload.projectID == projectID.rawValue,
            cursorPayload.kindBinding == kind?.rawValue ?? "",
            cursorPayload.originBinding == origin?.rawValue ?? "",
            !cursorPayload.knowledgeEntryID.isEmpty
        else { throw ContextCursorFailure.invalid }
        return Position(
            createdAt: cursorPayload.createdAt,
            knowledgeEntryID: cursorPayload.knowledgeEntryID)
    }

    private static func isURLSafeBase64Character(_ character: Character) -> Bool {
        character.isASCII
            && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }

    struct Position {
        let createdAt: Int64
        let knowledgeEntryID: String
    }

    private struct Payload: Codable {
        let version: Int
        let operation: String
        let workspacePath: String
        let generation: UUID
        let projectID: String
        let kindBinding: String
        let originBinding: String
        let createdAt: Int64
        let knowledgeEntryID: String
    }
}
