import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var viewModel: EarbudsViewModel
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
        .containerBackground(.thinMaterial, for: .window)
        .mainWindowBehavior(title: currentPageTitle)
        .frame(minWidth: 512, idealWidth: 648, maxWidth: 768, minHeight: 720, idealHeight: 840, maxHeight: 1440)
        .navigationTitle(currentPageTitle)
        .onAppear {
            selectCurrentDeviceIfNeeded()
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
            if let device = testDeviceStore.device(for: id) {
                HomePageView(
                    viewModel: viewModel,
                    displayState: device.displayState,
                    transitionNamespace: deviceTransitionNamespace
                )
            } else {
                HomePageView(viewModel: viewModel, transitionNamespace: deviceTransitionNamespace)
            }
#else
            HomePageView(viewModel: viewModel, transitionNamespace: deviceTransitionNamespace)
#endif
        case .logs:
            LogsPageView(viewModel: viewModel)
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

    private func updateDevicePageIfNeeded() {
        if case .device(let id) = currentPage {
#if DEBUG
            if testDeviceStore.device(for: id) != nil {
                return
            }
#endif
            currentPage = .device(currentDevice.id)
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(EarbudsViewModel())
}
