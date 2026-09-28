import AnchorPlatformMacOS
import Foundation

@MainActor
struct AnchorMacCompositionRoot {
    let applicationDisplayName: String
    let menuBarSymbolName: String
    let contextEngine: AnchorMacContextEngine

    private let applicationPurposeDescription: String

    init(
        applicationDisplayName: String,
        applicationPurposeDescription: String,
        menuBarSymbolName: String,
        contextEngine: AnchorMacContextEngine? = nil
    ) {
        self.applicationDisplayName = applicationDisplayName
        self.applicationPurposeDescription = applicationPurposeDescription
        self.menuBarSymbolName = menuBarSymbolName
        self.contextEngine =
            contextEngine
            ?? AnchorMacContextEngine.configuredForProduction(
                supportDirectoryURL: AnchorMacContextEngine.defaultSupportDirectoryURL,
                applicationBundleURL: Bundle.main.bundleURL)
    }

    func makeRootView() -> AnchorMacRootView {
        AnchorMacRootView(
            applicationDisplayName: applicationDisplayName,
            applicationPurposeDescription: applicationPurposeDescription,
            contextEngine: contextEngine
        )
    }
}
