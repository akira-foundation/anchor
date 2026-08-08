import AnchorSharedUI
import SwiftUI

struct AnchorMobileRootView: View {
    let applicationDisplayName: String
    let applicationPurposeDescription: String

    var body: some View {
        NavigationSplitView {
            List {
                Text(applicationDisplayName)
            }
            .navigationTitle(applicationDisplayName)
        } detail: {
            AnchorShellHeader(
                titleText: applicationDisplayName,
                subtitleText: applicationPurposeDescription
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }
}
