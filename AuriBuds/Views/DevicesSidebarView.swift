import SwiftUI

struct DevicesSidebarView: View {
    @ObservedObject var viewModel: EarbudsViewModel
    @Binding var currentPage: MainWindowPage
#if DEBUG
    @ObservedObject var testDeviceStore: DebugTestDeviceStore
#endif
    let errorLogCount: Int

    private var devices: [PairedDevice] {
#if DEBUG
        return viewModel.availableDisplayDevices(testDevices: testDeviceStore.devices)
#else
        return viewModel.pairedDevices
#endif
    }

    var body: some View {
        List {
            Section() {
                ForEach(devices) { device in
                    DeviceSidebarRow(
                        device: device,
                        connectionStatus: connectionStatus(for: device),
                        isSelected: currentPage == .device(device.id)
                    ) {
                        select(.device(device.id))
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: -8, bottom: 4, trailing: -8))
                    .listRowBackground(Color.clear)
                }
            }
            Section() {
                SidebarNavigationRow(
                    title: "日志",
                    systemImage: "doc.text",
                    badgeCount: errorLogCount,
                    isSelected: currentPage == .logs
                ) {
                    select(.logs)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: -8, bottom: 4, trailing: -8))
                .listRowBackground(Color.clear)

                SidebarNavigationRow(
                    title: "设置",
                    systemImage: "gearshape",
                    isSelected: currentPage == .settings
                ) {
                    select(.settings)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: -8, bottom: 4, trailing: -8))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("设备")
    }

    private func select(_ page: MainWindowPage) {
        withAnimation(.snappy(duration: 0.24)) {
            currentPage = page
        }
    }

    private func connectionStatus(for device: PairedDevice) -> ConnectionStatus {
        if let connectionStatusOverride = device.connectionStatusOverride {
            return connectionStatusOverride
        }

        guard device.isAppControllable else {
            return .disconnected
        }

        if device.id == PairedDevice(state: viewModel.state).id {
            return viewModel.state.connectionStatus
        }

        return .disconnected
    }
}

private struct SidebarNavigationRow: View {
    let title: String
    let systemImage: String
    var badgeCount = 0
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Label {
                    Text(title)
                        .font(.system(size: 14).weight(.semibold))
                } icon: {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 22, alignment: .center)
                }

                Spacer()

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.system(size: 12).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.red, in: Capsule())
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackground, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectionBackground: Color {
        isSelected ? Color.primary.opacity(0.10) : Color.clear
    }
}

private struct DeviceSidebarRow: View {
    @EnvironmentObject private var viewModel: EarbudsViewModel
    let device: PairedDevice
    let connectionStatus: ConnectionStatus
    let isSelected: Bool
    let action: () -> Void
    private var imageName: String? {
        device.selectedImageName ?? device.defaultImageName
    }

    @State private var blinkStatusDot = false

    private var statusDotColor: Color {
        switch connectionStatus {
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
        switch connectionStatus {
        case .connecting, .handshaking, .reconnecting:
            return true
        default:
            return false
        }
    }

    private var statusTitle: String {
        if device.connectionStatusOverride != nil {
            return connectionStatus.localizedTitle
        }

        return device.isAppControllable ? connectionStatus.localizedTitle : "不可连接"
    }

    init(
        device: PairedDevice,
        connectionStatus: ConnectionStatus,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.device = device
        self.connectionStatus = connectionStatus
        self.isSelected = isSelected
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if device.isAppControllable {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("刷新电量") {
                    Task {
                        await viewModel.refreshBattery()
                    }
                }
                .disabled(!canRefreshBattery)

                Button("重连") {
                    Task {
                        await viewModel.connect(device: device)
                    }
                }
                .disabled(viewModel.isBusy)

                Button("连接") {
                    Task {
                        await viewModel.connect(device: device)
                    }
                }
                .disabled(!canConnect)
            }
        } else {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            HStack() {
                DeviceImageView(
                    imageName: imageName,
                    fallbackSystemName: device.fallbackSystemName,
                    size: CGSize(width: 38, height: 38)
                )
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.system(size: 15))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    statusDot

                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(connectionStatus == .connected ? .green : .secondary)
                }
            }

            Spacer()
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 6, height: 6)
            .opacity(shouldBlinkStatusDot ? (blinkStatusDot ? 0.25 : 1.0) : 1.0)
            .onAppear {
                updateBlinking(isBlinking: shouldBlinkStatusDot)
            }
            .onChange(of: shouldBlinkStatusDot) { _, isBlinking in
                updateBlinking(isBlinking: isBlinking)
            }
    }

    private var selectionBackground: Color {
        isSelected ? Color.primary.opacity(0.10) : Color.clear
    }

    private var canRefreshBattery: Bool {
        device.id == PairedDevice(state: viewModel.state).id &&
            viewModel.state.connectionStatus == .connected &&
            !viewModel.isBusy
    }

    private var canConnect: Bool {
        guard !viewModel.isBusy else { return false }
        guard device.isAppControllable else { return false }

        switch viewModel.state.connectionStatus {
        case .disconnected, .error, .handshakeFailed:
            return true
        case .connected, .connecting, .handshaking, .reconnecting:
            return device.id != PairedDevice(state: viewModel.state).id
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
