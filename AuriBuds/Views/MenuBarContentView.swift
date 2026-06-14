import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var viewModel: EarbudsViewModel
    @Environment(\.openWindow) private var openWindow
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {

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
            }

            HStack() {
                BatteryRowView(value: viewModel.state.battery.text(for: .left)) {
                    Image(systemName: "l.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Left")
                }

                BatteryRowView(value: viewModel.state.battery.text(for: .right)) {
                    Image(systemName: "r.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Right")
                }

                BatteryRowView(value: viewModel.state.battery.text(for: .batteryCase)) {
                    BatteryCaseChargingIcon(isCharging: viewModel.state.battery.isCharging(.batteryCase))
                }
            }
            GeometryReader { geometry in
                DeviceImageView(
                    imageName: DeviceImageProvider.shared.primaryImageName(for: viewModel.state),
                    fallbackSystemName: viewModel.state.currentDevice?.fallbackSystemName ?? "headphones"
                )
                .frame(width: geometry.size.width, height: geometry.size.width)
                .scaleEffect(1)
                .position(x: geometry.size.width / 2, y: geometry.size.width / 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .clipped()

            Divider()

            ANCModeSelector(viewModel: viewModel, size: .compact)
                .disabled(viewModel.state.connectionStatus != .connected)

            Divider()
            Button("打开主窗口") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            if let lastError = viewModel.state.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 320)
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
}

#Preview {
    MenuBarContentView()
        .environmentObject(EarbudsViewModel())
}
