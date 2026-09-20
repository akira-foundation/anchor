import AnchorApplication
import Foundation

enum SQLiteContextCursorOperation: String, Sendable {
    case searchProject = "search-project"
    case listSessions = "list-sessions"
    case loadConversationEntries = "load-conversation-entries"
}

struct SQLiteContextCursorPosition: Sendable, Equatable {
    let timestamp: Int64
    let identifier: String
}

enum SQLiteContextTimestamp {
    private static let microsecondsPerSecond = 1_000_000.0

    static func microseconds(sinceUnixEpochFor date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * microsecondsPerSecond).rounded())
    }

    static func date(fromUnixMicroseconds microseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(microseconds) / microsecondsPerSecond)
    }
}

enum SQLiteContextCursor {
    private static let schemaVersion = 1

    static func encode(
        operation: SQLiteContextCursorOperation,
        scopeBinding: String,
        filterBinding: String,
        position: SQLiteContextCursorPosition
    ) throws -> ContextPageCursor {
        let payload = Payload(
            version: schemaVersion,
            operation: operation.rawValue,
            scopeBinding: scopeBinding,
            filterBinding: filterBinding,
            lastSortTimestamp: position.timestamp,
            lastIdentifier: position.identifier)

        do {
            let encodedPayload = try JSONEncoder().encode(payload)
            let token = encodedPayload.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            guard let cursor = ContextPageCursor(rawValue: token) else {
                throw ContextCursorFailure.invalid
            }
            return cursor
        } catch {
            throw ContextCursorFailure.invalid
        }
    }

    static func decode(
        _ cursor: ContextPageCursor?,
        operation: SQLiteContextCursorOperation,
        scopeBinding: String,
        filterBinding: String
    ) throws -> SQLiteContextCursorPosition? {
        guard let cursor else { return nil }
        guard cursor.rawValue.allSatisfy(Self.isURLSafeBase64Character) else {
            throw ContextCursorFailure.invalid
        }

        var encodedPayload = cursor.rawValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - encodedPayload.count % 4) % 4
        encodedPayload.append(String(repeating: "=", count: paddingCount))

        guard let payloadBytes = Data(base64Encoded: encodedPayload),
            let payload = try? JSONDecoder().decode(Payload.self, from: payloadBytes),
            payload.version == schemaVersion,
            payload.operation == operation.rawValue,
            payload.scopeBinding == scopeBinding,
            payload.filterBinding == filterBinding,
            !payload.lastIdentifier.isEmpty
        else {
            throw ContextCursorFailure.invalid
        }

        return SQLiteContextCursorPosition(
            timestamp: payload.lastSortTimestamp,
            identifier: payload.lastIdentifier)
    }

    private static func isURLSafeBase64Character(_ character: Character) -> Bool {
        character.isASCII
            && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }

    private struct Payload: Codable {
        let version: Int
        let operation: String
        let scopeBinding: String
        let filterBinding: String
        let lastSortTimestamp: Int64
        let lastIdentifier: String
    }
}
