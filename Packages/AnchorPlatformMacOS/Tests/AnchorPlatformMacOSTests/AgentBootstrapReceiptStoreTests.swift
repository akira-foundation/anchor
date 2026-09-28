import AnchorApplication
import Foundation
import Testing

@testable import AnchorPlatformMacOS

struct AgentBootstrapReceiptStoreTests {
    @Test("receipts round-trip exact definitions independently for each client")
    func exactReceiptRoundTrip() async throws {
        let directoryURL = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = AgentBootstrapReceiptStore(directoryURL: directoryURL)
        let receipt = makeReceipt()
        try await store.record(receipt)
        #expect(try await store.load(for: .claudeCode) == receipt)
        #expect(try await store.load(for: .codex) == nil)
        let reopenedStore = AgentBootstrapReceiptStore(directoryURL: directoryURL)
        #expect(try await reopenedStore.load(for: .claudeCode) == receipt)
    }

    @Test("replacement swaps the file atomically without modifying open readers")
    func replacementPreservesOpenReader() async throws {
        let directoryURL = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = AgentBootstrapReceiptStore(directoryURL: directoryURL)
        try await store.record(makeReceipt())
        let receiptURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: nil
            ).first)
        let originalBytes = try Data(contentsOf: receiptURL)
        let reader = try FileHandle(forReadingFrom: receiptURL)
        defer { try? reader.close() }
        let replacement = makeReceipt(configurationPath: "/other/config.json")
        try await store.record(replacement)
        #expect(try reader.readToEnd() == originalBytes)
        #expect(try await store.load(for: .claudeCode) == replacement)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).count == 1)
    }

    @Test("a receipt for another configuration path cannot prove ownership")
    func receiptIsBoundToConfigurationLocation() async throws {
        let directoryURL = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = AgentBootstrapReceiptStore(directoryURL: directoryURL)
        try await store.record(makeReceipt(configurationPath: "/first/.claude.json"))
        let receipt = try #require(try await store.load(for: .claudeCode))
        #expect(receipt.configurationPath == "/first/.claude.json")
        #expect(receipt.configurationPath != "/second/.claude.json")
    }

    @Test("absent receipts and repeated removal are harmless")
    func absentReceiptAndRemoval() async throws {
        let directoryURL = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = AgentBootstrapReceiptStore(directoryURL: directoryURL)
        #expect(try await store.load(for: .claudeCode) == nil)
        try await store.remove(for: .claudeCode)
        try await store.record(makeReceipt())
        try await store.remove(for: .claudeCode)
        #expect(try await store.load(for: .claudeCode) == nil)
    }

    @Test(
        "corrupt and unsupported receipts are refused", arguments: ["broken", "unsupportedVersion"])
    func corruptReceiptFails(contents: String) async throws {
        let directoryURL = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = AgentBootstrapReceiptStore(directoryURL: directoryURL)
        try await store.record(makeReceipt())
        let receiptURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: nil
            ).first)
        if contents == "unsupportedVersion" {
            var envelope = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any])
            envelope["version"] = 999
            try JSONSerialization.data(withJSONObject: envelope).write(to: receiptURL)
        } else {
            try Data(contents.utf8).write(to: receiptURL)
        }
        await #expect(throws: (any Error).self) { try await store.load(for: .claudeCode) }
    }

    private func makeDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func makeReceipt(
        configurationPath: String = "/users/é space/.claude.json"
    ) -> AgentBootstrapReceipt {
        AgentBootstrapReceipt(
            client: .claudeCode, configurationPath: configurationPath,
            definition: AgentMCPDefinition(
                command: "/app é/AnchorMCPServer",
                arguments: ["--workspace", "/workspace 空"],
                environment: ["EXPLICIT": "setting"]))
    }
}
