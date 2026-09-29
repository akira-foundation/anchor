import AnchorApplication
import Darwin
import Foundation

struct AgentBootstrapReceipt: Codable, Equatable, Sendable {
    let client: AgentClient
    let configurationPath: String
    let definition: AgentMCPDefinition
}

actor AgentBootstrapReceiptStore {
    private struct Envelope: Codable {
        let version: Int
        let receipt: AgentBootstrapReceipt
    }

    let directoryURL: URL
    let persistence: AgentBootstrapFilePersistence

    init(directoryURL: URL, persistence: AgentBootstrapFilePersistence = .init()) {
        self.directoryURL = directoryURL
        self.persistence = persistence
    }

    func load(for client: AgentClient) throws -> AgentBootstrapReceipt? {
        guard let bytes = try persistence.readIfPresent(receiptURL(for: client))
        else { return nil }
        let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard envelope.version == 1, envelope.receipt.client == client else {
            throw AgentBootstrapPersistenceError.invalidRecord
        }
        return envelope.receipt
    }

    func record(_ receipt: AgentBootstrapReceipt) throws {
        try persistence.createDirectory(directoryURL)
        try persistence.removePendingFiles(in: directoryURL)
        let bytes = try JSONEncoder().encode(Envelope(version: 1, receipt: receipt))
        try persistence.replace(bytes, at: receiptURL(for: receipt.client))
    }

    func remove(for client: AgentClient) throws {
        try persistence.removeFile(receiptURL(for: client))
    }

    private func receiptURL(for client: AgentClient) -> URL {
        directoryURL.appendingPathComponent("\(client.rawValue).json")
    }
}

enum AgentBootstrapPersistenceError: Error {
    case invalidRecord
    case transactionExists
    case unsupportedConfiguration
}

struct AgentBootstrapFilePersistence: Sendable {
    enum Checkpoint: Equatable, Sendable {
        case createdDirectory(URL)
        case synchronizedDirectory(URL)
        case publishedFile(URL)
        case preparedFile(URL)
        case removingFile(URL)
        case renamedFile(URL)
        case removedFile(URL)
        case validatingMutationState(URL)
    }

    let checkpoint: @Sendable (Checkpoint) throws -> Void

    init(checkpoint: @escaping @Sendable (Checkpoint) throws -> Void = { _ in }) {
        self.checkpoint = checkpoint
    }

    func createDirectory(_ directoryURL: URL) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw AgentBootstrapPersistenceError.unsupportedConfiguration
            }
            try synchronizeAncestorEntries(of: directoryURL)
            return
        } catch CocoaError.fileReadNoSuchFile {}
        let parentURL = directoryURL.deletingLastPathComponent()
        try createDirectory(parentURL)
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try checkpoint(.createdDirectory(directoryURL))
        try synchronizeDirectory(parentURL)
    }

    private func synchronizeAncestorEntries(of directoryURL: URL) throws {
        guard directoryURL.path != "/" else { return }
        let parentURL = directoryURL.deletingLastPathComponent()
        try synchronizeAncestorEntries(of: parentURL)
        try synchronizeDirectory(parentURL)
    }

    func removeFile(_ fileURL: URL) throws {
        try checkpoint(.removingFile(fileURL))
        var attributes = stat()
        guard lstat(fileURL.path, &attributes) == 0 else {
            if errno == ENOENT {
                try synchronizeNearestDirectory(fileURL.deletingLastPathComponent())
                return
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard attributes.st_mode & S_IFMT == S_IFREG else {
            throw AgentBootstrapPersistenceError.unsupportedConfiguration
        }
        guard Darwin.unlink(fileURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try checkpoint(.removedFile(fileURL))
        try synchronizeDirectory(fileURL.deletingLastPathComponent())
    }

    func removePendingFiles(in directoryURL: URL) throws {
        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile { return }
        for fileURL in fileURLs {
            let filename = fileURL.lastPathComponent
            guard filename.hasPrefix("."), filename.hasSuffix(".pending"),
                UUID(uuidString: String(filename.dropFirst().dropLast(8))) != nil
            else { continue }
            try removeFile(fileURL)
        }
    }

    func readIfPresent(_ fileURL: URL) throws -> Data? {
        do {
            return try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    func replace(
        _ bytes: Data, at destinationURL: URL, permissions: Int = 0o600,
        recoveryTemporaryURL: URL? = nil
    ) throws {
        guard (0...0o7777).contains(permissions) else {
            throw AgentBootstrapPersistenceError.invalidRecord
        }
        let directoryURL = destinationURL.deletingLastPathComponent()
        let temporaryURL =
            recoveryTemporaryURL
            ?? directoryURL.appendingPathComponent(".\(UUID().uuidString).pending")
        let descriptor = Darwin.open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? writer.close()
            if recoveryTemporaryURL == nil { _ = Darwin.unlink(temporaryURL.path) }
        }
        try writer.write(contentsOf: bytes)
        guard fchmod(descriptor, mode_t(permissions)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try writer.synchronize()
        try checkpoint(.preparedFile(temporaryURL))
        guard Darwin.rename(temporaryURL.path, destinationURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try checkpoint(.renamedFile(destinationURL))
        try synchronizeDirectory(directoryURL)
        try checkpoint(.publishedFile(destinationURL))
    }

    func synchronizeDirectory(_ directoryURL: URL) throws {
        let descriptor = Darwin.open(directoryURL.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try checkpoint(.synchronizedDirectory(directoryURL))
    }

    private func synchronizeNearestDirectory(_ directoryURL: URL) throws {
        do {
            try synchronizeDirectory(directoryURL)
        } catch let error as POSIXError where error.code == .ENOENT && directoryURL.path != "/" {
            try synchronizeNearestDirectory(directoryURL.deletingLastPathComponent())
        }
    }
}
