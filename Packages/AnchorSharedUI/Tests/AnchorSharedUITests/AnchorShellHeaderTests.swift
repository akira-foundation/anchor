import Testing

@testable import AnchorSharedUI

@Suite("AnchorShellHeader")
@MainActor
struct AnchorShellHeaderTests {
    @Test("the header exposes the title and subtitle it was created with")
    func headerExposesTheTitleAndSubtitleItWasCreatedWith() {
        let shellHeader = AnchorShellHeader(titleText: "Anchor", subtitleText: "Persistent context layer")

        #expect(shellHeader.titleText == "Anchor")
        #expect(shellHeader.subtitleText == "Persistent context layer")
    }
}
