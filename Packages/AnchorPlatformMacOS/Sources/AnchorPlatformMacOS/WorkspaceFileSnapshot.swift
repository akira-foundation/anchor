import CryptoKit
import Foundation

struct WorkspaceFileSnapshot: Sendable {
    enum CaptureFailure: Error { case incomplete }

    let isComplete: Bool
    private let fingerprints: [String: SHA256.Digest]

    var knownPaths: Set<String> { Set(fingerprints.keys) }

    static func capture(at workspaceURL: URL) -> Self {
        let watchedPaths =
            SuperpowersArtifactLocation.allCases.flatMap(\.pathsOnDisk)
            + [GraphifyArtifactProvider.outputDirectory]
        var fingerprints: [String: SHA256.Digest] = [:]
        var isComplete = true
        for watchedPath in watchedPaths {
            let directoryURL = workspaceURL.appending(path: watchedPath)
            do {
                guard
                    try directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                else { continue }
            } catch let failure as CocoaError where failure.code == .fileReadNoSuchFile {
                continue
            } catch {
                isComplete = false
                continue
            }
            guard
                let descendants = FileManager.default.enumerator(
                    at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey],
                    errorHandler: { _, _ in
                        isComplete = false
                        return false
                    })
            else {
                isComplete = false
                continue
            }
            for case let fileURL as URL in descendants {
                do {
                    guard
                        let relativePath = WorkspacePath.relativePath(
                            of: fileURL.path, under: workspaceURL),
                        try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile
                            == true
                    else { continue }
                    let contents = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                    fingerprints[relativePath] = SHA256.hash(data: contents)
                } catch {
                    isComplete = false
                }
            }
        }
        return Self(isComplete: isComplete, fingerprints: fingerprints)
    }

    func changedPaths(since baseline: Self) -> Set<String> {
        Set(fingerprints.keys).union(baseline.fingerprints.keys).filter {
            fingerprints[$0] != baseline.fingerprints[$0]
        }
    }
}
