public protocol ValidatedRawValue: Codable, Sendable {
    static var rawValueRequirement: String { get }

    var rawValue: String { get }

    init?(rawValue: String)
}

extension ValidatedRawValue {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedRawValue = try container.decode(String.self)

        guard let decodedValue = Self(rawValue: decodedRawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: Self.rawValueRequirement
            )
        }

        self = decodedValue
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
