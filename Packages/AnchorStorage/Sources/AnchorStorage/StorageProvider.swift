import Foundation

public protocol StorageProvider: Sendable {
    func writeStoredData(_ storedData: Data, toRelativePath relativePath: String) async throws
    func readStoredData(atRelativePath relativePath: String) async throws -> Data
}
