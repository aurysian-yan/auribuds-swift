import SwiftUI

struct HomePageView: View {
    @ObservedObject var viewModel: EarbudsViewModel
    var displayState: DeviceDisplayState? = nil
    let transitionNamespace: Namespace.ID

    private var activeState: DeviceDisplayState {
        displayState ?? DeviceDisplayState(viewModel: viewModel)
    }

    private var isUsingLiveDevice: Bool {
        displayState == nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                MainWindowCard {
                    DeviceOverviewContent(
                        displayState: activeState,
                        transitionNamespace: transitionNamespace
                    )
                }

                MainWindowCard {
                    if isUsingLiveDevice {
                        ANCModeSelector(viewModel: viewModel, size: .regular)
                            .disabled(viewModel.state.connectionStatus != .connected)
                    } else {
                        ANCModeSummaryView(title: activeState.ancModeTitle)
                    }
                }

                MainWindowCard {
                    connectionActions
                        .disabled(!isUsingLiveDevice)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .animation(.snappy(duration: 0.32), value: activeState)
    }

    private var connectionActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接")
                .font(.headline)

            HStack(spacing: 10) {
                Button("刷新电量") {
                    Task {
                        await viewModel.refreshBattery()
                    }
                }
                .disabled(!isUsingLiveDevice || viewModel.state.connectionStatus != .connected || viewModel.isBusy)

                Button("重连") {
                    Task {
                        await viewModel.reconnect()
                    }
                }
                .disabled(!isUsingLiveDevice || viewModel.isBusy)

                if !isUsingLiveDevice ||
                    viewModel.state.connectionStatus == .disconnected ||
                    viewModel.state.connectionStatus == .error ||
                    viewModel.state.connectionStatus == .handshakeFailed {
                    Button("连接") {
                        Task {
                            await viewModel.connect()
                        }
                    }
                    .disabled(!isUsingLiveDevice || viewModel.isBusy)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DeviceDisplayState: Equatable {
    let deviceName: String
    let connectionStatus: ConnectionStatus
    let leftBatteryText: String
    let rightBatteryText: String
    let caseBatteryText: String
    let isCaseCharging: Bool
    let imageName: String?
    let fallbackSystemName: String
    let ancModeTitle: String

    init(
        deviceName: String,
        connectionStatus: ConnectionStatus,
        leftBatteryText: String,
        rightBatteryText: String,
        caseBatteryText: String,
        isCaseCharging: Bool,
        imageName: String?,
        fallbackSystemName: String,
        ancModeTitle: String
    ) {
        self.deviceName = deviceName
        self.connectionStatus = connectionStatus
        self.leftBatteryText = leftBatteryText
        self.rightBatteryText = rightBatteryText
        self.caseBatteryText = caseBatteryText
        self.isCaseCharging = isCaseCharging
        self.imageName = imageName
        self.fallbackSystemName = fallbackSystemName
        self.ancModeTitle = ancModeTitle
    }

    @MainActor
    init(viewModel: EarbudsViewModel) {
        let state = viewModel.state

        deviceName = state.deviceName
        connectionStatus = state.connectionStatus
        leftBatteryText = state.battery.text(for: .left)
        rightBatteryText = state.battery.text(for: .right)
        caseBatteryText = state.battery.text(for: .batteryCase)
        isCaseCharging = state.battery.isCharging(.batteryCase)
        imageName = DeviceImageProvider.shared.primaryImageName(for: state)
        fallbackSystemName = state.currentDevice?.fallbackSystemName ?? "headphones"
        ancModeTitle = state.ancMode.localizedTitle
    }
}

struct DeviceOverviewContent: View {
    let displayState: DeviceDisplayState
    let transitionNamespace: Namespace.ID
    @State private var blinkStatusDot = false

    private var statusDotColor: Color {
        switch displayState.connectionStatus {
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
        switch displayState.connectionStatus {
        case .connecting, .handshaking, .reconnecting:
            return true
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                        .opacity(shouldBlinkStatusDot ? (blinkStatusDot ? 0.25 : 1.0) : 1.0)
                        .onAppear {
                            updateBlinking(isBlinking: shouldBlinkStatusDot)
                        }
                        .onChange(of: shouldBlinkStatusDot) { _, isBlinking in
                            updateBlinking(isBlinking: isBlinking)
                        }

                    Text(displayState.connectionStatus.localizedTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.interpolate)
                        .matchedGeometryEffect(id: "device-status-title", in: transitionNamespace)
                }
                .matchedGeometryEffect(id: "device-status-row", in: transitionNamespace)

                Text(displayState.deviceName)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .fontWidth(.compressed)
                    .lineLimit(2)
                    .contentTransition(.interpolate)
                    .matchedGeometryEffect(id: "device-title", in: transitionNamespace)
            }

            HStack {
                BatteryRowView(value: displayState.leftBatteryText) {
                    Image(systemName: "l.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Left")
                }

                BatteryRowView(value: displayState.rightBatteryText) {
                    Image(systemName: "r.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Right")
                }

                BatteryRowView(value: displayState.caseBatteryText) {
                    BatteryCaseChargingIcon(isCharging: displayState.isCaseCharging)
                }
            }
            .matchedGeometryEffect(id: "device-battery-row", in: transitionNamespace)

            GeometryReader { geometry in
                DeviceImageView(
                    imageName: displayState.imageName,
                    fallbackSystemName: displayState.fallbackSystemName
                )
                .frame(width: geometry.size.width, height: geometry.size.width)
                .position(x: geometry.size.width / 2, y: geometry.size.width / 2)
                .matchedGeometryEffect(id: "device-image", in: transitionNamespace)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }

    private func updateBlinking(isBlinking: Bool) {
        blinkStatusDot = false

        if isBlinking {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                blinkStatusDot = true
            }
        }
    }
}

private struct ANCModeSummaryView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("降噪模式")
                .font(.headline)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
