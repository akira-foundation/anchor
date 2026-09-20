import AnchorApplication
import AnchorDomain
import Foundation

enum ArtifactContextCursor {
    private static let version = 1

    static func encode(
        after record: ArtifactContextRecord?,
        projectID: ProjectID,
        providerBinding: String
    ) throws -> ContextPageCursor? {
        guard let record, let revision = record.latestRevision else { return nil }

        let payload = Payload(
            version: version,
            projectID: projectID.rawValue,
            providerBinding: providerBinding,
            revisedAt: SQLiteArtifactContextStore.revisedAt(for: revision.createdAt),
            artifactID: record.artifact.id.rawValue)
        let encodedPayload = try JSONEncoder().encode(payload)
        let token = encodedPayload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        guard let cursor = ContextPageCursor(rawValue: token) else {
            throw ContextCursorFailure.invalid
        }
        return cursor
    }

    static func decode(
        _ cursor: ContextPageCursor?,
        projectID: ProjectID,
        providerBinding: String
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
            let payload = try? JSONDecoder().decode(Payload.self, from: payloadBytes),
            payload.version == version,
            payload.projectID == projectID.rawValue,
            payload.providerBinding == providerBinding,
            !payload.artifactID.isEmpty
        else { throw ContextCursorFailure.invalid }

        return Position(revisedAt: payload.revisedAt, artifactID: payload.artifactID)
    }

    private static func isURLSafeBase64Character(_ character: Character) -> Bool {
        character.isASCII
            && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }

    struct Position {
        let revisedAt: Int64
        let artifactID: String
    }

    private struct Payload: Codable {
        let version: Int
        let projectID: String
        let providerBinding: String
        let revisedAt: Int64
        let artifactID: String
    }
}
