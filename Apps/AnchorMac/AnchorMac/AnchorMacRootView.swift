import AnchorSharedUI
import SwiftUI

struct AnchorMacRootView: View {
    let applicationDisplayName: String
    let applicationPurposeDescription: String

    var body: some View {
        AnchorShellHeader(
            titleText: applicationDisplayName,
            subtitleText: applicationPurposeDescription
        )
        .frame(width: 320, alignment: .topLeading)
        .padding(16)
    }
}
