import AnchorApplication
import AnchorDomain
import AnchorSearch
import Foundation

public struct SearchedTranscriptIndex: AgentTranscriptIndexing {
    private let search: any ContextSearching

    public init(search: any ContextSearching) {
        self.search = search
    }

    public func indexTranscript(_ transcript: AgentTranscript) async throws {
        try await search.indexTranscript(transcript)
    }
}
