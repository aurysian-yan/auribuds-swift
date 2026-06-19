import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: EarbudsViewModel
    @State private var selection: MainWindowPage?
    @Namespace private var deviceTransitionNamespace
#if DEBUG
    @StateObject private var testDeviceStore = DebugTestDeviceStore.shared
#endif

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(devices) { device in
                        NavigationLink(value: MainWindowPage.device(device.id)) {
                            IOSDeviceRow(
                                device: device,
                                connectionStatus: connectionStatus(for: device)
                            )
                        }
                    }
                } header: {
                    Text("已配对的设备")
                }

                Section {
                    NavigationLink(value: MainWindowPage.findDevices) {
                        Label("查找设备", systemImage: "magnifyingglass")
                    }

                    NavigationLink(value: MainWindowPage.logs) {
                        Label {
                            HStack {
                                Text("日志")

                                if errorLogCount > 0 {
                                    Spacer()
                                    Text(errorLogCount > 99 ? "99+" : "\(errorLogCount)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .frame(minWidth: 18, minHeight: 18)
                                        .background(.red, in: Capsule())
                                }
                            }
                        } icon: {
                            Image(systemName: "doc.text")
                        }
                    }

                    NavigationLink(value: MainWindowPage.settings) {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("设备")
        } detail: {
            pageContent(for: selection ?? defaultPage)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if selection == nil {
                selection = defaultPage
            }
        }
        .onChange(of: currentDevice.id) { _, id in
            if hasLiveDevice {
                if selection == nil || selection == .home {
                    selection = .device(id)
                }
            }
        }
    }

    private var hasLiveDevice: Bool {
        viewModel.state.currentDevice != nil || !viewModel.state.availableDevices.isEmpty
    }

    private var defaultPage: MainWindowPage {
        hasLiveDevice ? .device(currentDevice.id) : .home
    }

    private var currentDevice: PairedDevice {
        PairedDevice(state: viewModel.state)
    }

    private var devices: [PairedDevice] {
#if DEBUG
        return viewModel.availableDisplayDevices(testDevices: testDeviceStore.devices)
#else
        return viewModel.pairedDevices
#endif
    }

    private var errorLogCount: Int {
        var count = 0

        if viewModel.state.lastError != nil {
            count += 1
        }

        count += viewModel.debugEvents.filter { event in
            let lowercased = event.lowercased()

            return lowercased.contains("error") ||
                lowercased.contains("failed") ||
                lowercased.contains("失败") ||
                lowercased.contains("错误")
        }.count

        return count
    }

    @ViewBuilder
    private func pageContent(for page: MainWindowPage) -> some View {
        switch page {
        case .home:
            HomePageView(viewModel: viewModel, transitionNamespace: deviceTransitionNamespace)
        case .device(let id):
#if DEBUG
            if let testDevice = testDeviceStore.device(for: id) {
                HomePageView(
                    viewModel: viewModel,
                    displayState: testDevice.displayState,
                    transitionNamespace: deviceTransitionNamespace
                )
            } else if let device = devices.first(where: { $0.id == id }), device.id != currentDevice.id {
                HomePageView(
                    viewModel: viewModel,
                    displayState: DeviceDisplayState(device: device),
                    transitionNamespace: deviceTransitionNamespace
                )
            } else {
                HomePageView(viewModel: viewModel, transitionNamespace: deviceTransitionNamespace)
            }
#else
            if let device = devices.first(where: { $0.id == id }), device.id != currentDevice.id {
                HomePageView(
                    viewModel: viewModel,
                    displayState: DeviceDisplayState(device: device),
                    transitionNamespace: deviceTransitionNamespace
                )
            } else {
                HomePageView(viewModel: viewModel, transitionNamespace: deviceTransitionNamespace)
            }
#endif
        case .logs:
            LogsPageView(viewModel: viewModel)
        case .findDevices:
            FindDeviceView(viewModel: viewModel)
        case .settings:
#if DEBUG
            SettingsPageView(viewModel: viewModel, testDeviceStore: testDeviceStore)
#else
            SettingsPageView(viewModel: viewModel)
#endif
        }
    }

    private func pageTitle(_ page: MainWindowPage) -> String {
        switch page {
        case .home:
            return ""
        case .device(let id):
            return devices.first { $0.id == id }?.displayName ?? currentDevice.displayName
        case .findDevices:
            return "查找设备"
        case .logs:
            return "日志"
        case .settings:
            return "设置"
        }
    }

    private func connectionStatus(for device: PairedDevice) -> ConnectionStatus {
        if let connectionStatusOverride = device.connectionStatusOverride {
            return connectionStatusOverride
        }

        guard device.isAppControllable else {
            return .disconnected
        }

        if device.id == currentDevice.id {
            return viewModel.state.connectionStatus
        }

        return .disconnected
    }
}

private struct IOSDeviceRow: View {
    let device: PairedDevice
    let connectionStatus: ConnectionStatus

    private var imageName: String? {
        device.selectedImageName ?? device.defaultImageName
    }

    private var statusDotColor: Color {
        switch connectionStatus {
        case .connected:
            return .green
        case .disconnected:
            return .secondary
        case .connecting, .handshaking, .reconnecting:
            return .accentColor
        case .error, .handshakeFailed, .deviceNotFound:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            DeviceImageView(
                imageName: imageName,
                fallbackSystemName: device.fallbackSystemName,
                size: CGSize(width: 38, height: 38)
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.system(size: 15))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)

                    Text(connectionStatus.localizedTitle)
                        .font(.caption)
                        .foregroundStyle(connectionStatus == .connected ? .green : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .environmentObject(EarbudsViewModel())
}
