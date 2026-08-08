import SwiftUI

@main
struct AnchorMobileApp: App {
    private let compositionRoot = AnchorMobileCompositionRoot(
        applicationDisplayName: "Anchor",
        applicationPurposeDescription: "Persistent context layer for AI-assisted development"
    )

    var body: some Scene {
        WindowGroup {
            compositionRoot.makeRootView()
        }
    }
}
