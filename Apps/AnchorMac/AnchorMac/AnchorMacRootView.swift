import AnchorSharedUI
import SwiftUI

struct AnchorMacRootView: View {
    let applicationDisplayName: String
    let applicationPurposeDescription: String
    let contextEngine: AnchorMacContextEngine

    var body: some View {
        let presentation = AnchorMacStatusPresentation(state: contextEngine.state)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AnchorShellHeader(
                    titleText: applicationDisplayName,
                    subtitleText: applicationPurposeDescription)

                VStack(alignment: .leading, spacing: 4) {
                    if let projectName = presentation.projectName {
                        Text(projectName).font(.headline)
                    }
                    Text(presentation.statusText).foregroundStyle(.secondary)
                }

                ForEach(presentation.rows, id: \.title) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                        Spacer()
                        Text(row.statusText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.callout)
                }

                if let guidanceText = presentation.guidanceText {
                    Text(guidanceText).font(.caption).foregroundStyle(.secondary)
                }

                AgentIntegrationStatusView(
                    report: contextEngine.agentBootstrapReport,
                    isRunning: contextEngine.isAgentBootstrapRunning,
                    retry: contextEngine.retryAgentBootstrap)

                Divider()
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let workspaceURL = contextEngine.agentBootstrapWorkspaceURL {
                            Text("Authorized workspace: \(workspaceURL.path)")
                        }
                        Text("MCP server: \(contextEngine.helperExecutableURL.path)")
                        if let diagnosticText = presentation.diagnosticText {
                            Text(diagnosticText)
                        }
                    }
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                .font(.caption)
            }
            .padding(16)
        }
        .frame(width: 360, height: 440)
        .task { await contextEngine.refreshRefusals() }
    }
}
