import SwiftUI

struct StatusHeaderView: View {
    @ObservedObject var viewModel: EarbudsViewModel
    @State private var isDebugExpanded = false
    @State private var blinkStatusDot = false
    
    private var statusDotColor: Color {
        switch viewModel.state.connectionStatus {
        case .connected:
            return .green

        case .disconnected:
            return .secondary

        case .connecting, .handshaking, .reconnecting:
            return .accentColor

        case .error, .handshakeFailed:
            return .yellow
        }
    }

    private var shouldBlinkStatusDot: Bool {
        switch viewModel.state.connectionStatus {
        case .connecting, .handshaking, .reconnecting:
            return true
        default:
            return false
        }
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            DeviceImageView(
                imageName: DeviceImageProvider.shared.primaryImageName(for: viewModel.state),
                fallbackSystemName: viewModel.state.currentDevice?.fallbackSystemName ?? "headphones",
                size: CGSize(width: 112, height: 112)
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                        .opacity(shouldBlinkStatusDot ? (blinkStatusDot ? 0.25 : 1.0) : 1.0)
                        .onAppear {
                            blinkStatusDot = false

                            if shouldBlinkStatusDot {
                                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                                    blinkStatusDot = true
                                }
                            }
                        }
                        .onChange(of: shouldBlinkStatusDot) { _, isBlinking in
                            blinkStatusDot = false

                            if isBlinking {
                                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                                    blinkStatusDot = true
                                }
                            }
                        }

                    Text(viewModel.state.connectionStatus.localizedTitle)
                        .font(.callout) // 比 caption 大一号
                        .foregroundStyle(.secondary) // 文字颜色固定，不跟状态变
                }

                Text(viewModel.state.deviceName)
                    .font(.largeTitle)
                    .lineLimit(2)
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
