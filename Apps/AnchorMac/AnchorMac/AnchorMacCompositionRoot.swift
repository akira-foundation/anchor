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
        contextEngine: AnchorMacContextEngine = AnchorMacContextEngine()
    ) {
        self.applicationDisplayName = applicationDisplayName
        self.applicationPurposeDescription = applicationPurposeDescription
        self.menuBarSymbolName = menuBarSymbolName
        self.contextEngine = contextEngine
    }

    func makeRootView() -> AnchorMacRootView {
        AnchorMacRootView(
            applicationDisplayName: applicationDisplayName,
            applicationPurposeDescription: applicationPurposeDescription,
            contextEngine: contextEngine
        )
    }
}
