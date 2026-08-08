import AnchorFoundation
import Foundation

public struct StorageKey: ValidatedRawValue, Hashable, CustomStringConvertible {
    public static let maximumLength = 1024

    public static var rawValueRequirement: String {
        "Storage key is empty, absolute, over-long, or does not consist of plain relative segments"
    }

    private static let rejectedScalars: Set<Unicode.Scalar> = ["\\", "%"]

    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty, rawValue.utf8.count <= Self.maximumLength else { return nil }
        guard rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        guard !rawValue.hasPrefix("/") else { return nil }
        guard rawValue.unicodeScalars.allSatisfy(Self.isPermittedScalar) else { return nil }

        let segments = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.allSatisfy(Self.isPermittedSegment) else { return nil }

        self.rawValue = rawValue
    }

    private static func isPermittedScalar(_ scalar: Unicode.Scalar) -> Bool {
        guard !rejectedScalars.contains(scalar) else { return false }

        return !scalar.properties.isDefaultIgnorableCodePoint
            && !CharacterSet.controlCharacters.contains(scalar)
    }

    private static func isPermittedSegment(_ segment: Substring) -> Bool {
        guard !segment.isEmpty, segment != ".", segment != ".." else { return false }

        return segment == segment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var description: String { rawValue }
}
