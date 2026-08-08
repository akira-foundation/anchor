@MainActor
struct AnchorMacCompositionRoot {
    let applicationDisplayName: String
    let menuBarSymbolName: String

    private let applicationPurposeDescription: String

    init(
        applicationDisplayName: String,
        applicationPurposeDescription: String,
        menuBarSymbolName: String
    ) {
        self.applicationDisplayName = applicationDisplayName
        self.applicationPurposeDescription = applicationPurposeDescription
        self.menuBarSymbolName = menuBarSymbolName
    }

    func makeRootView() -> AnchorMacRootView {
        AnchorMacRootView(
            applicationDisplayName: applicationDisplayName,
            applicationPurposeDescription: applicationPurposeDescription
        )
    }
}
