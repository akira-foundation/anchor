import SwiftUI

@main
struct AnchorMacApp: App {
    private let compositionRoot = AnchorMacCompositionRoot(
        applicationDisplayName: "Anchor",
        applicationPurposeDescription: "Persistent context layer for AI-assisted development",
        menuBarSymbolName: "point.3.filled.connected.trianglepath.dotted"
    )

    init() {
        let engine = compositionRoot.contextEngine

        Task { await engine.start() }
    }

    var body: some Scene {
        MenuBarExtra(
            compositionRoot.applicationDisplayName,
            systemImage: compositionRoot.menuBarSymbolName
        ) {
            compositionRoot.makeRootView()
        }
        .menuBarExtraStyle(.window)
    }
}
