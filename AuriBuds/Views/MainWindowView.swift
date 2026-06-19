import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var viewModel: EarbudsViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentPage: MainWindowPage = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Namespace private var deviceTransitionNamespace
#if DEBUG
    @StateObject private var testDeviceStore = DebugTestDeviceStore.shared
#endif

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
#if DEBUG
                DevicesSidebarView(
                    viewModel: viewModel,
                    currentPage: $currentPage,
                    testDeviceStore: testDeviceStore,
                    errorLogCount: errorLogCount
                )
#else
                DevicesSidebarView(
                    viewModel: viewModel,
                    currentPage: $currentPage,
                    errorLogCount: errorLogCount
                )
#endif
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            VStack(spacing: 0) {
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 18)
            }
            .background(.thinMaterial)
        }
            .background(.thinMaterial)
#if os(macOS)
            .containerBackground(.thinMaterial, for: .window)
#endif
#if os(macOS)
            .mainWindowBehavior(title: currentPageTitle)
            .frame(minWidth: 512, idealWidth: 648, maxWidth: 768, minHeight: 720, idealHeight: 840, maxHeight: 1440)
#else
            .frame(minWidth: 320, idealWidth: 648, maxWidth: .infinity, minHeight: 480, idealHeight: 840, maxHeight: .infinity)
#endif
            .navigationTitle(currentPageTitle)
        .onAppear {
            selectCurrentDeviceIfNeeded()
        }
        .onChange(of: currentPage) { _, page in
            updateColumnVisibility(for: page)
        }
        .onChange(of: currentDevice.id) { _, _ in
            updateDevicePageIfNeeded()
        }
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

    private var currentPageTitle: String {
        switch currentPage {
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
    private var pageContent: some View {
        switch currentPage {
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

    private func selectCurrentDeviceIfNeeded() {
        if currentPage == .home {
            currentPage = .device(currentDevice.id)
        }
    }

    private func updateColumnVisibility(for page: MainWindowPage) {
#if os(iOS)
        guard horizontalSizeClass == .compact else { return }
        columnVisibility = page == .home ? .all : .detailOnly
#endif
    }

    private func updateDevicePageIfNeeded() {
        if case .device(let id) = currentPage {
#if DEBUG
            if testDeviceStore.device(for: id) != nil {
                return
            }
#endif
            if !devices.contains(where: { $0.id == id }) {
                currentPage = .device(currentDevice.id)
            }
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(EarbudsViewModel())
}
