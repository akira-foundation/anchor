import AnchorSearch
import Foundation

public struct AssembledSessionContext: Sendable {
    public let search: any ContextSearching
    public let recorder: any SessionContextRecording
    public let rebuilder: DiscoveredSessionContextRebuilder
}
