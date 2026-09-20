import AnchorDomain
import Foundation

enum ArtifactChunkCursor {
    private struct Payload: Codable {
        let version: Int
        let operation: String
        let project: String
        let artifact: String
        let revision: String
        let offset: Int
    }

    static func offset(
        _ cursor: ContextPageCursor?, project: ProjectID, artifact: ArtifactID,
        revision: RevisionID
    ) throws -> Int {
        guard let cursor else { return 0 }
        guard
            cursor.rawValue.allSatisfy({
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
            })
        else { throw ContextCursorFailure.invalid }
        var token = cursor.rawValue.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
            of: "_", with: "/")
        token.append(String(repeating: "=", count: (4 - token.count % 4) % 4))
        guard let bytes = Data(base64Encoded: token),
            let payload = try? JSONDecoder().decode(Payload.self, from: bytes),
            payload.version == 1, payload.operation == "read-artifact",
            payload.project == project.rawValue,
            payload.artifact == artifact.rawValue, payload.revision == revision.rawValue,
            payload.offset > 0
        else { throw ContextCursorFailure.invalid }
        return payload.offset
    }

    static func encode(
        offset: Int, project: ProjectID, artifact: ArtifactID, revision: RevisionID
    )
        throws -> ContextPageCursor
    {
        let payload = Payload(
            version: 1, operation: "read-artifact", project: project.rawValue,
            artifact: artifact.rawValue, revision: revision.rawValue, offset: offset)
        let token = try JSONEncoder().encode(payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard let cursor = ContextPageCursor(rawValue: token) else {
            throw ContextCursorFailure.invalid
        }
        return cursor
    }
}
