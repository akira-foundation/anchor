import AnchorApplication
import AnchorPlatformMacOS
import SwiftUI

struct AgentIntegrationStatusView: View {
    let report: AgentClientBootstrapReport?
    let isRunning: Bool
    let retry: () -> Void

    var body: some View {
        let presentation = AgentClientBootstrapPresentation(report: report)
        if report != nil || isRunning {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                Text("Agent integrations").font(.headline)
                if isRunning {
                    Text("Checking integrations…").foregroundStyle(.secondary)
                }
                ForEach(presentation.rows, id: \.client) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(row.clientName)
                            Spacer()
                            Text(row.statusText).foregroundStyle(.secondary)
                        }
                        if let guidanceText = row.guidanceText {
                            Text(guidanceText).foregroundStyle(.secondary)
                        }
                    }
                }
                if presentation.canRetry {
                    Button("Retry integrations", action: retry).disabled(isRunning)
                }
            }
            .font(.caption)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

}
