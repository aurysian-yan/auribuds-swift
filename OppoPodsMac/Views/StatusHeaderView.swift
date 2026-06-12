import SwiftUI

struct StatusHeaderView: View {
    @ObservedObject var viewModel: EarbudsViewModel

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OppoPodsMac")
                    .font(.title2.weight(.semibold))

                Text(viewModel.state.deviceName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(viewModel.state.connectionStatus.localizedTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(statusColor)

                Text("最近刷新：\(refreshText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var refreshText: String {
        guard let lastRefreshDate = viewModel.lastRefreshDate else {
            return "--"
        }

        return Self.timeFormatter.string(from: lastRefreshDate)
    }

    private var statusColor: Color {
        switch viewModel.state.connectionStatus {
        case .connected:
            return .green
        case .connecting, .handshaking, .reconnecting:
            return .secondary
        case .error, .handshakeFailed:
            return .red
        case .disconnected:
            return .secondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

#Preview {
    StatusHeaderView(viewModel: EarbudsViewModel())
        .padding()
}
