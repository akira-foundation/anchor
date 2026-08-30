import Foundation

public enum ToolOutput {
    public static let maximumByteCount = 10_000
    public static let keptPrefixByteCount = 4_000
    public static let keptSuffixByteCount = 4_000

    public static func rendered(_ value: Any?) -> String {
        if let text = value as? String { return text }

        guard let blocks = value as? [[String: Any]] else { return encoded(value) }

        return blocks.map(rendered(block:)).joined(separator: "\n")
    }

    public static func abridged(_ text: String) -> String {
        guard text.utf8.count > maximumByteCount else { return text }

        let bytes = Array(text.utf8)
        let head = String(decoding: bytes.prefix(keptPrefixByteCount), as: UTF8.self)
        let tail = String(decoding: bytes.suffix(keptSuffixByteCount), as: UTF8.self)
        let omittedBytes = bytes.count - keptPrefixByteCount - keptSuffixByteCount
        let omittedLines = text.reduce(into: 0) { total, character in
            total += character == "\n" ? 1 : 0
        }

        return head + marker(omittedBytes: omittedBytes, ofLines: omittedLines) + tail
    }

    public static func summarised(_ value: Any?) -> String {
        abridged(rendered(value))
    }

    private static func marker(omittedBytes: Int, ofLines lines: Int) -> String {
        "\n[omitted \(omittedBytes) bytes of \(lines) lines]\n"
    }

    private static func rendered(block: [String: Any]) -> String {
        guard block["type"] as? String == "image" else {
            if let text = block["text"] as? String { return text }

            return encoded(block)
        }

        let source = block["source"] as? [String: Any] ?? [:]
        let mediaType = source["media_type"] as? String ?? "image"
        let byteCount = (source["data"] as? String)?.utf8.count ?? 0

        return "[image omitted: \(mediaType), \(byteCount) encoded bytes]"
    }

    private static func encoded(_ value: Any?) -> String {
        guard let value,
            let data = try? JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "" }

        return String(decoding: data, as: UTF8.self)
    }
}
