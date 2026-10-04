import AppKit
import Foundation
import SwiftUI
import Testing

@MainActor
struct AnchorMacMenuLayoutTests {
    @Test func menuProvidesVisibleHeightWithoutAParentProposal() {
        let engine = AnchorMacContextEngine(
            supportDirectoryURL: nil, agentBootstrapLifecycle: nil,
            helperExecutableURL: URL(
                filePath: "/Applications/Anchor.app/Contents/Helpers/AnchorMCPServer"))
        let hostingView = NSHostingView(
            rootView: AnchorMacRootView(
                applicationDisplayName: "Anchor",
                applicationPurposeDescription: "Persistent context",
                contextEngine: engine))
        #expect(hostingView.fittingSize.width >= 320)
        #expect(hostingView.fittingSize.height >= 200)
    }
}
