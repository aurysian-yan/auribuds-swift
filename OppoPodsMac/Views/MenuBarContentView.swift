import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: EarbudsViewModel
    @State private var isDebugExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.state.deviceName)
                    .font(.headline)
                Text(viewModel.state.connectionStatus.localizedTitle)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                BatteryRowView(title: "Left", value: viewModel.state.battery.text(for: .left))
                BatteryRowView(title: "Right", value: viewModel.state.battery.text(for: .right))
                BatteryRowView(title: "Case", value: viewModel.state.battery.text(for: .batteryCase))
            }

            Divider()

            ANCModeSelector(viewModel: viewModel)
                .disabled(viewModel.state.connectionStatus != .connected)

            HStack {
                Button("刷新") {
                    Task {
                        await viewModel.refreshBattery()
                    }
                }
                .disabled(viewModel.state.connectionStatus != .connected || viewModel.isBusy)

                Button("重连") {
                    Task {
                        await viewModel.reconnect()
                    }
                }
                .disabled(viewModel.isBusy)

                if viewModel.state.connectionStatus == .disconnected || viewModel.state.connectionStatus == .error || viewModel.state.connectionStatus == .handshakeFailed {
                    Button("连接") {
                        Task {
                            await viewModel.connect()
                        }
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            if let lastError = viewModel.state.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            DisclosureGroup(isExpanded: $isDebugExpanded) {
                DebugLogView(events: viewModel.debugEvents)
                    .padding(.top, 4)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug Log")
                    if !isDebugExpanded, let latest = viewModel.latestDebugEvent {
                        Text(latest)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .opacity(0.65)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 320)
        .onAppear {
            viewModel.start()
        }
    }

    private var statusColor: Color {
        switch viewModel.state.connectionStatus {
        case .connected:
            return .green
        case .connecting:
            return .secondary
        case .error, .handshakeFailed:
            return .red
        case .disconnected:
            return .secondary
        }
    }
}

#Preview {
    MenuBarContentView(viewModel: EarbudsViewModel())
}
