import Foundation

public enum PublishedContextDecodingFailure: Error, Sendable, Equatable {
    case unsupportedFormatVersion(Int)
}

public enum PublishedContextCodec {
    static let currentFormatVersion = 1

    public static func encode<Body: Encodable>(_ body: Body) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(
            PublishedEnvelope(formatVersion: currentFormatVersion, body: body))
    }

    public static func decode<Body: Decodable>(
        _ type: Body.Type, from contents: Data
    ) throws -> Body {
        let formatVersion = try JSONDecoder().decode(FormatVersionProbe.self, from: contents)
            .formatVersion
        guard formatVersion == currentFormatVersion else {
            throw PublishedContextDecodingFailure.unsupportedFormatVersion(formatVersion)
        }

        return try JSONDecoder().decode(DecodedEnvelope<Body>.self, from: contents).body
    }
}

private struct PublishedEnvelope<Body: Encodable>: Encodable {
    let formatVersion: Int
    let body: Body
}

private struct DecodedEnvelope<Body: Decodable>: Decodable {
    let body: Body
}

private struct FormatVersionProbe: Decodable {
    let formatVersion: Int
}
