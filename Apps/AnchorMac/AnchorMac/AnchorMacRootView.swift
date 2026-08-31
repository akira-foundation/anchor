import AnchorSharedUI
import SwiftUI

struct AnchorMacRootView: View {
    let applicationDisplayName: String
    let applicationPurposeDescription: String
    let contextEngine: AnchorMacContextEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnchorShellHeader(
                titleText: applicationDisplayName,
                subtitleText: applicationPurposeDescription
            )

            Text(engineStatusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 320, alignment: .topLeading)
        .padding(16)
        .task { await contextEngine.refreshRefusals() }
    }

    private func refusalSuffix(_ refusals: [String]) -> String {
        guard let latest = refusals.last else { return "" }

        return "\nlatest refusal: \(latest)"
    }

    private var engineStatusText: String {
        switch contextEngine.state {
        case .idle:
            return "Not watching yet"
        case .watching(let projectName, .synchronized, let refusals):
            return "Watching \(projectName), synchronized with iCloud"
                + refusalSuffix(refusals)
        case .watching(let projectName, .localOnlyUntilAccountReturns, let refusals):
            return "Watching \(projectName), on this Mac only. iCloud was unreachable at launch"
                + refusalSuffix(refusals)
        case .noWorkspaceConfigured:
            return "No workspace configured"
        case .failed(let description):
            return "Stopped: \(description)"
        }
    }
}
