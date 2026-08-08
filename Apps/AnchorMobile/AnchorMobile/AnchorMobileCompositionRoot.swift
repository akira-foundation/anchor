@MainActor
struct AnchorMobileCompositionRoot {
    private let applicationDisplayName: String
    private let applicationPurposeDescription: String

    init(applicationDisplayName: String, applicationPurposeDescription: String) {
        self.applicationDisplayName = applicationDisplayName
        self.applicationPurposeDescription = applicationPurposeDescription
    }

    func makeRootView() -> AnchorMobileRootView {
        AnchorMobileRootView(
            applicationDisplayName: applicationDisplayName,
            applicationPurposeDescription: applicationPurposeDescription
        )
    }
}
