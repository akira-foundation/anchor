import AnchorApplication
import Foundation

public actor ContextReadModelStatusStore: ContextAvailabilityReading {
    private struct GenerationState: Codable {
        let identifier: UUID
        let available: Bool
    }
    public struct Update: Sendable, Hashable {
        fileprivate let identifier: UUID
    }

    private let markerURL: URL
    private let generationURL: URL
    private var generation = UUID()
    private var activeUpdates: Set<Update> = []
    private var activeRebuild: Update?
    private(set) var pendingUpdates: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var needsRecovery = false

    public init(supportDirectoryURL: URL) {
        let location = ContextReadModelLocation(supportDirectoryURL: supportDirectoryURL)
        markerURL = location.rebuildMarkerURL
        generationURL = location.generationURL
    }

    public func requireAvailable() throws {
        _ = try loadAvailableGeneration()
    }

    public func loadAvailableGeneration() throws -> ContextReadGeneration {
        guard !FileManager.default.fileExists(atPath: markerURL.path(percentEncoded: false)) else {
            throw ContextQueryFailure.contextUnavailable
        }
        guard
            let state = try? JSONDecoder().decode(
                GenerationState.self, from: Data(contentsOf: generationURL)), state.available
        else { throw ContextQueryFailure.contextUnavailable }
        return ContextReadGeneration(identifier: state.identifier)
    }

    public func markRebuildRequired() throws {
        try FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        generation = UUID()
        try writeGeneration(available: false)
        try Data("rebuild-required\n".utf8).write(to: markerURL, options: .atomic)
        needsRecovery = true
    }

    public func beginUpdate(rebuilding: Bool = false) async throws -> Update {
        guard !rebuilding || activeUpdates.isEmpty else {
            throw ContextQueryFailure.contextUnavailable
        }
        while !rebuilding, activeRebuild != nil {
            try await waitForRebuild()
        }
        try Task.checkCancellation()
        let alreadyStale =
            FileManager.default.fileExists(
                atPath: markerURL.path(percentEncoded: false))
            || (FileManager.default.fileExists(atPath: generationURL.path())
                && (try? loadAvailableGeneration()) == nil)
        let retainedFailure = activeUpdates.isEmpty ? alreadyStale && !rebuilding : needsRecovery
        try markRebuildRequired()
        needsRecovery = retainedFailure
        let update = Update(identifier: UUID())
        activeUpdates.insert(update)
        if rebuilding { activeRebuild = update }
        return update
    }

    public func completeUpdate(_ update: Update, succeeded: Bool) throws {
        guard activeUpdates.remove(update) != nil else { throw ContextQueryFailure.readFailed }
        defer {
            if activeRebuild == update {
                activeRebuild = nil
                let waiting = pendingUpdates.values
                pendingUpdates.removeAll()
                for continuation in waiting { continuation.resume() }
            }
        }
        needsRecovery = needsRecovery || !succeeded
        guard activeUpdates.isEmpty, !needsRecovery else { return }
        try FileManager.default.removeItem(at: markerURL)
        try writeGeneration(available: true)
    }

    private func waitForRebuild() async throws {
        let identifier = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    pendingUpdates[identifier] = continuation
                }
            }
        } onCancel: {
            Task { await self.resumeCancelledUpdate(identifier) }
        }
        try Task.checkCancellation()
    }

    private func resumeCancelledUpdate(_ identifier: UUID) {
        pendingUpdates.removeValue(forKey: identifier)?.resume()
    }

    private func writeGeneration(available: Bool) throws {
        let state = GenerationState(identifier: generation, available: available)
        try JSONEncoder().encode(state).write(to: generationURL, options: .atomic)
    }
}
