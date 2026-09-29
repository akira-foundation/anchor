import Foundation
import Testing

@testable import AnchorPlatformMacOS

@Suite("Agent command runner")
struct AgentCommandRunnerTests {
    @Test("runner removes inherited configuration overrides before launching a command")
    func removedEnvironmentKeysAreAbsent() async throws {
        let output = try await FoundationAgentCommandRunner(
            inheritedEnvironment: ["CLAUDE_CONFIG_DIR": "/unrelated/config"]
        ).run(
            AgentCommand(
                executableURL: URL(filePath: "/usr/bin/printenv"), arguments: ["CLAUDE_CONFIG_DIR"],
                removedEnvironmentKeys: ["CLAUDE_CONFIG_DIR"]))
        #expect(output.terminationStatus == 1)
        #expect(output.standardOutput.isEmpty)
    }

    @Test("runner uses the requested working directory for project scope resolution")
    func requestedWorkingDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("requested workspace".utf8).write(
            to: directory.appendingPathComponent("scope-marker"))
        let output = try await FoundationAgentCommandRunner().run(
            AgentCommand(
                executableURL: URL(filePath: "/bin/cat"), arguments: ["scope-marker"],
                workingDirectoryURL: directory))
        #expect(output.terminationStatus == 0)
        #expect(output.standardOutput == Data("requested workspace".utf8))
    }

    @Test("runner passes paths with spaces and Unicode as untouched argument tokens")
    func argumentsRemainSeparateTokens() async throws {
        let executableURL = try makeExecutable(
            named: "print arguments",
            script: "#!/bin/sh\nprintf '%s\\n' \"$1\" \"$2\"\n"
        )
        let command = AgentCommand(
            executableURL: executableURL,
            arguments: ["/tmp/Project à quotes ' and spaces", "second token"]
        )

        let output = try await FoundationAgentCommandRunner().run(command)

        #expect(output.terminationStatus == 0)
        #expect(
            String(decoding: output.standardOutput, as: UTF8.self)
                == "/tmp/Project à quotes ' and spaces\nsecond token\n")
    }

    @Test("runner bounds stdout and stderr without deadlocking")
    func commandOutputIsBounded() async throws {
        let executableURL = try makeExecutable(
            named: "large output",
            script: "#!/bin/sh\nhead -c 131072 /dev/zero >&2\nhead -c 131072 /dev/zero\n"
        )

        let output = try await FoundationAgentCommandRunner().run(
            AgentCommand(executableURL: executableURL, arguments: []))

        #expect(output.terminationStatus == 0)
        #expect(output.standardOutput.count == 65_536)
        #expect(output.standardError.count == 65_536)
    }

    @Test("runner reports nonzero termination without throwing away output")
    func nonzeroExitIsACommandOutput() async throws {
        let executableURL = try makeExecutable(
            named: "failed command",
            script: "#!/bin/sh\nprintf 'out'\nprintf 'error' >&2\nexit 23\n"
        )

        let output = try await FoundationAgentCommandRunner().run(
            AgentCommand(executableURL: executableURL, arguments: []))

        #expect(output.terminationStatus == 23)
        #expect(output.standardOutput == Data("out".utf8))
        #expect(output.standardError == Data("error".utf8))
    }

    @Test("caller cancellation stops a running command")
    func callerCancellationStopsCommand() async throws {
        let executableURL = try makeExecutable(
            named: "slow command", script: "#!/bin/sh\nsleep 2\n")
        let commandTask = Task {
            try await FoundationAgentCommandRunner().run(
                AgentCommand(executableURL: executableURL, arguments: []))
        }
        try await Task.sleep(for: .milliseconds(100))

        commandTask.cancel()

        do {
            _ = try await commandTask.value
            Issue.record("A cancelled command returned normally")
        } catch is CancellationError {
        }
    }

    @Test("a command exceeding its execution deadline is stopped")
    func commandDeadlineStopsHungProcess() async throws {
        let executableURL = try makeExecutable(
            named: "deadline command", script: "#!/bin/sh\nsleep 2\n")
        let startedAt = ContinuousClock.now

        do {
            _ = try await FoundationAgentCommandRunner(maximumRunDuration: 0.2).run(
                AgentCommand(executableURL: executableURL, arguments: []))
            Issue.record("A command that exceeded its deadline returned normally")
        } catch AgentCommandRunFailure.timedOut {
            #expect(startedAt.duration(to: .now) < .seconds(1))
        }
    }

    @Test("ordinary commands can outlive the short discovery deadline")
    func ordinaryCommandCanExceedDiscoveryDeadline() async throws {
        let executableURL = try makeExecutable(
            named: "slow verification", script: "#!/bin/sh\nsleep 6\nprintf 'verified'\n")

        let output = try await FoundationAgentCommandRunner().run(
            AgentCommand(executableURL: executableURL, arguments: []))

        #expect(output.terminationStatus == 0)
        #expect(output.standardOutput == Data("verified".utf8))
    }

    @Test("an exited command does not wait for a descendant holding its output pipes")
    func inheritedPipeHandlesDoNotBlockCompletion() async throws {
        let executableURL = try makeExecutable(
            named: "background child", script: "#!/bin/sh\nsleep 2 &\nprintf 'ready'\n")
        let startedAt = ContinuousClock.now

        let output = try await FoundationAgentCommandRunner().run(
            AgentCommand(executableURL: executableURL, arguments: []))

        #expect(output.terminationStatus == 0)
        #expect(output.standardOutput == Data("ready".utf8))
        #expect(startedAt.duration(to: .now) < .seconds(1))
    }

    @Test(
        "rapid exited commands do not block while descendants hold their output pipes",
        .timeLimit(.minutes(1)))
    func concurrentExitedCommandsDoNotBlockAfterExit() async throws {
        let runner = FoundationAgentCommandRunner()
        let executableURL = URL(filePath: "/bin/sh")

        for _ in 0..<20 {
            try await withThrowingTaskGroup(of: AgentCommandOutput.self) { commandGroup in
                for _ in 0..<32 {
                    commandGroup.addTask {
                        try await runner.run(
                            AgentCommand(
                                executableURL: executableURL,
                                arguments: ["-c", "sleep 0.25 & printf ready"]))
                    }
                }

                for try await output in commandGroup {
                    #expect(output.terminationStatus == 0)
                    #expect(output.standardOutput == Data("ready".utf8))
                }
            }
        }
    }

    private func makeExecutable(named name: String, script: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "anchor-agent-runner-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let executableURL = directoryURL.appending(path: name)
        try Data(script.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        return executableURL
    }
}
