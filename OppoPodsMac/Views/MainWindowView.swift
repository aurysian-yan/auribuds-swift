import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var viewModel: EarbudsViewModel

    var body: some View {
        VStack(spacing: 0) {
            StatusHeaderView(viewModel: viewModel)
                .padding()

            Divider()

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    batterySection

                    ANCModeSelector(viewModel: viewModel, size: .regular)
                        .disabled(viewModel.state.connectionStatus != .connected)

                    actionSection

                    if let lastError = viewModel.state.lastError {
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                DebugLogPanelView(events: viewModel.debugEvents)
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("电量")
                .font(.headline)

            HStack(spacing: 12) {
                BatteryCardView(title: "Left", value: viewModel.state.battery.text(for: .left))
                BatteryCardView(title: "Right", value: viewModel.state.battery.text(for: .right))
                BatteryCardView(title: "Case", value: viewModel.state.battery.text(for: .batteryCase))
            }
        }
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            Button("刷新电量") {
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
    }
}

#Preview {
    MainWindowView()
        .environmentObject(EarbudsViewModel())
}
