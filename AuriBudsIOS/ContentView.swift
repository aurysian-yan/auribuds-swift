import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: EarbudsViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Namespace private var deviceTransitionNamespace
    @State private var selection: MainWindowPage?
    @State private var showDeviceList = false
    @State private var selectedDeviceID: String?
#if DEBUG
    @StateObject private var testDeviceStore = DebugTestDeviceStore.shared
#endif

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: - iPad

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("已配对的设备") {
                    ForEach(devices) { device in
                        NavigationLink(value: MainWindowPage.device(device.id)) {
                            IOSDeviceRow(
                                device: device,
                                connectionStatus: connectionStatus(for: device)
                            )
                        }
                    }
                }

                Section {
                    NavigationLink(value: MainWindowPage.findDevices) {
                        Label("查找设备", systemImage: "magnifyingglass")
                    }
                    NavigationLink(value: MainWindowPage.logs) {
                        Label("日志", systemImage: "doc.text")
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

    // MARK: - iPhone

    private var iPhoneLayout: some View {
        TabView {
            NavigationStack {
                homePageContent
                    .navigationTitle("AuriBuds")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showDeviceList = true
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                        }
                    }
            }
            .tabItem {
                Label("主页", systemImage: "house.fill")
            }

            NavigationStack {
                settingsView
                    .navigationTitle("设置")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }

            NavigationStack {
                LogsPageView(viewModel: viewModel)
                    .navigationTitle("日志")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("日志", systemImage: "doc.text.fill")
            }
            .badge(errorLogCount)
        }
        .sheet(isPresented: $showDeviceList) {
            deviceListSheet
        }
    }

    // MARK: - Device List Sheet

    private var deviceListSheet: some View {
        NavigationStack {
            Form {
                Section("已配对的设备") {
                    ForEach(devices) { device in
                        Button {
                            selectedDeviceID = device.id
                            showDeviceList = false
                        } label: {
                            IOSDeviceRow(
                                device: device,
                                connectionStatus: connectionStatus(for: device)
                            )
                        }
                    }
                }

                Section {
                    NavigationLink {
                        FindDeviceView(viewModel: viewModel)
                    } label: {
                        Label("查找设备", systemImage: "magnifyingglass")
                    }
                }
            }
            .navigationTitle("设备")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Shared

    @ViewBuilder
    private var homePageContent: some View {
        if let id = selectedDeviceID, let device = devices.first(where: { $0.id == id }) {
            HomePageView(
                viewModel: viewModel,
                displayState: DeviceDisplayState(device: device),
                transitionNamespace: deviceTransitionNamespace
            )
        } else {
            HomePageView(
                viewModel: viewModel,
                transitionNamespace: deviceTransitionNamespace
            )
        }
    }

    @ViewBuilder
    private var settingsView: some View {
#if DEBUG
        SettingsPageView(viewModel: viewModel, testDeviceStore: testDeviceStore)
#else
        SettingsPageView(viewModel: viewModel)
#endif
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
}

// MARK: - Device Row

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
