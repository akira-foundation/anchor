import AnchorStorage
import Foundation

enum CloudChangeCursor {
    private static let separator: Character = "#"

    static func cursor(pageToken: Data?, entryIndex: Int) -> StorageCursor {
        let encodedToken = pageToken.map { $0.base64EncodedString() } ?? ""

        return StorageCursor(rawValue: "\(encodedToken)\(separator)\(entryIndex)")
    }

    static func resumePoint(from cursor: StorageCursor?) -> (pageToken: Data?, entriesToSkip: Int) {
        guard let cursor else { return (nil, 0) }

        let parts = cursor.rawValue.split(
            separator: separator, maxSplits: 1, omittingEmptySubsequences: false)

        guard parts.count == 2, let entryIndex = Int(parts[1]) else { return (nil, 0) }

        let encodedToken = String(parts[0])

        guard !encodedToken.isEmpty else { return (nil, entryIndex + 1) }

        return (Data(base64Encoded: encodedToken), entryIndex + 1)
    }
}
