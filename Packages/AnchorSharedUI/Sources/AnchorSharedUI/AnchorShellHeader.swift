import SwiftUI

public struct AnchorShellHeader: View {
    public let titleText: String
    public let subtitleText: String

    public init(titleText: String, subtitleText: String) {
        self.titleText = titleText
        self.subtitleText = subtitleText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleText)
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text(subtitleText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
