public protocol Action<Input, Output>: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    func perform(_ input: Input) async throws -> Output
}
