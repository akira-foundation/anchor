import Darwin
import Foundation

struct AgentCommand: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let maximumRunDuration: TimeInterval?
    let workingDirectoryURL: URL?
    let removedEnvironmentKeys: Set<String>

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        maximumRunDuration: TimeInterval? = nil,
        workingDirectoryURL: URL? = nil,
        removedEnvironmentKeys: Set<String> = []
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.maximumRunDuration = maximumRunDuration
        self.workingDirectoryURL = workingDirectoryURL
        self.removedEnvironmentKeys = removedEnvironmentKeys
    }
}

struct AgentCommandOutput: Sendable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data

    init(terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

protocol AgentCommandRunning: Sendable {
    func run(_ command: AgentCommand) async throws -> AgentCommandOutput
}

enum AgentCommandRunFailure: Error {
    case timedOut
    case outputReadFailed
}

struct FoundationAgentCommandRunner: AgentCommandRunning {
    private let maximumCapturedByteCount: Int
    private let maximumRunDuration: TimeInterval
    private let inheritedEnvironment: [String: String]

    init(
        maximumCapturedByteCount: Int = 65_536, maximumRunDuration: TimeInterval = 35,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.maximumCapturedByteCount = max(0, maximumCapturedByteCount)
        self.maximumRunDuration = max(0.05, maximumRunDuration)
        self.inheritedEnvironment = inheritedEnvironment
    }

    func run(_ command: AgentCommand) async throws -> AgentCommandOutput {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectoryURL
        process.environment = inheritedEnvironment.merging(command.environment) {
            _, override in override
        }.filter { !command.removedEnvironmentKeys.contains($0.key) }

        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        let termination = AgentCommandTermination()
        process.terminationHandler = { terminatedProcess in
            termination.record(status: terminatedProcess.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            closePipe(standardOutputPipe)
            closePipe(standardErrorPipe)
            throw error
        }

        try? standardOutputPipe.fileHandleForWriting.close()
        try? standardErrorPipe.fileHandleForWriting.close()

        let cancellation = AgentCommandCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let output = try captureOutput(
                            from: process,
                            standardOutputPipe: standardOutputPipe,
                            standardErrorPipe: standardErrorPipe,
                            maximumRunDuration: command.maximumRunDuration.map { max(0.05, $0) }
                                ?? maximumRunDuration,
                            cancellation: cancellation,
                            termination: termination)
                        continuation.resume(returning: output)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.markCancelled()
        }
    }

    private func captureOutput(
        from process: Process,
        standardOutputPipe: Pipe,
        standardErrorPipe: Pipe,
        maximumRunDuration: TimeInterval,
        cancellation: AgentCommandCancellation,
        termination: AgentCommandTermination
    ) throws -> AgentCommandOutput {
        defer {
            try? standardOutputPipe.fileHandleForReading.close()
            try? standardErrorPipe.fileHandleForReading.close()
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        var childExitTime: TimeInterval?
        var standardOutput = Data()
        var standardError = Data()
        var outputOpen = true
        var errorOpen = true

        while true {
            let currentTime = ProcessInfo.processInfo.systemUptime
            if cancellation.isCancelled {
                stop(process, termination: termination)
                throw CancellationError()
            }
            if currentTime - startedAt >= maximumRunDuration {
                stop(process, termination: termination)
                throw AgentCommandRunFailure.timedOut
            }

            if termination.status != nil && childExitTime == nil {
                childExitTime = currentTime
            }
            if termination.status != nil && !outputOpen && !errorOpen {
                break
            }
            if let childExitTime, currentTime - childExitTime >= 0.1 {
                break
            }

            var descriptors = [
                pollfd(
                    fd: outputOpen ? standardOutputPipe.fileHandleForReading.fileDescriptor : -1,
                    events: Int16(POLLIN | POLLHUP), revents: 0),
                pollfd(
                    fd: errorOpen ? standardErrorPipe.fileHandleForReading.fileDescriptor : -1,
                    events: Int16(POLLIN | POLLHUP), revents: 0),
            ]
            let pollStatus = descriptors.withUnsafeMutableBufferPointer {
                Darwin.poll($0.baseAddress, nfds_t($0.count), 50)
            }
            if pollStatus < 0 && errno != EINTR {
                stop(process, termination: termination)
                throw AgentCommandRunFailure.outputReadFailed
            }
            do {
                if descriptors[0].revents != 0 {
                    try appendAvailableBytes(
                        from: descriptors[0].fd, to: &standardOutput, isOpen: &outputOpen)
                }
                if descriptors[1].revents != 0 {
                    try appendAvailableBytes(
                        from: descriptors[1].fd, to: &standardError, isOpen: &errorOpen)
                }
            } catch {
                stop(process, termination: termination)
                throw error
            }
        }

        guard let terminationStatus = termination.status else {
            stop(process, termination: termination)
            throw AgentCommandRunFailure.outputReadFailed
        }
        return AgentCommandOutput(
            terminationStatus: terminationStatus,
            standardOutput: standardOutput,
            standardError: standardError)
    }

    private func appendAvailableBytes(
        from descriptor: Int32,
        to capturedBytes: inout Data,
        isOpen: inout Bool
    ) throws {
        var buffer = [UInt8](repeating: 0, count: 8_192)
        let byteCount = buffer.withUnsafeMutableBytes {
            Darwin.read(descriptor, $0.baseAddress, $0.count)
        }
        if byteCount == 0 {
            isOpen = false
            return
        }
        if byteCount < 0 {
            guard errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR else {
                throw AgentCommandRunFailure.outputReadFailed
            }
            return
        }
        let remainingByteCount = maximumCapturedByteCount - capturedBytes.count
        if remainingByteCount > 0 {
            capturedBytes.append(contentsOf: buffer.prefix(min(byteCount, remainingByteCount)))
        }
    }

    private func stop(_ process: Process, termination: AgentCommandTermination) {
        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
        }
        termination.wait()
    }

    private func closePipe(_ pipe: Pipe) {
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
    }
}

private final class AgentCommandTermination: @unchecked Sendable {
    private let lock = NSLock()
    private let completion = DispatchSemaphore(value: 0)
    private var recordedStatus: Int32?

    var status: Int32? {
        lock.withLock { recordedStatus }
    }

    func record(status: Int32) {
        lock.withLock {
            recordedStatus = status
        }
        completion.signal()
    }

    func wait() {
        if status == nil {
            completion.wait()
        }
    }
}

private final class AgentCommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func markCancelled() {
        lock.withLock {
            cancelled = true
        }
    }
}
