import AppKit
import SwiftUI

private enum MainWindowPage: Hashable {
    case home
    case device(String)
    case logs
    case settings
}

struct MainWindowView: View {
    @EnvironmentObject private var viewModel: EarbudsViewModel
    @State private var currentPage: MainWindowPage = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DevicesSidebarView(
                viewModel: viewModel,
                currentPage: $currentPage,
                errorLogCount: errorLogCount
            )
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

    private var currentPageTitle: String {
        switch currentPage {
        case .home:
            return ""
        case .device:
            return currentDevice.displayName
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
        case .home, .device:
            HomePageView(viewModel: viewModel)
        case .logs:
            LogsPageView(viewModel: viewModel)
        case .settings:
            SettingsPageView(viewModel: viewModel)
        }
    }

    private func selectCurrentDeviceIfNeeded() {
        if currentPage == .home {
            currentPage = .device(currentDevice.id)
        }
    }

    private func updateDevicePageIfNeeded() {
        if case .device = currentPage {
            currentPage = .device(currentDevice.id)
        }
    }
}

struct HomePageView: View {
    @ObservedObject var viewModel: EarbudsViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                MainWindowCard {
                    DeviceOverviewContent(viewModel: viewModel)
                }

                MainWindowCard {
                    ANCModeSelector(viewModel: viewModel, size: .regular)
                        .disabled(viewModel.state.connectionStatus != .connected)
                }

                MainWindowCard {
                    connectionActions
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
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
                .disabled(viewModel.state.connectionStatus != .connected || viewModel.isBusy)

                Button("重连") {
                    Task {
                        await viewModel.reconnect()
                    }
                }
                .disabled(viewModel.isBusy)

                if viewModel.state.connectionStatus == .disconnected ||
                    viewModel.state.connectionStatus == .error ||
                    viewModel.state.connectionStatus == .handshakeFailed {
                    Button("连接") {
                        Task {
                            await viewModel.connect()
                        }
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DeviceOverviewContent: View {
    @ObservedObject var viewModel: EarbudsViewModel
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

                    Text(viewModel.state.connectionStatus.localizedTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.state.deviceName)
                    .font(.largeTitle)
                    .lineLimit(2)
            }

            HStack {
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
                .position(x: geometry.size.width / 2, y: geometry.size.width / 2)
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

private struct DevicesSidebarView: View {
    @ObservedObject var viewModel: EarbudsViewModel
    @Binding var currentPage: MainWindowPage
    let errorLogCount: Int

    private var devices: [PairedDevice] {
        viewModel.pairedDevices
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
    
    @State private var isDebugExpanded = false
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
        device.isAppControllable ? connectionStatus.localizedTitle : "不可连接"
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
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            HStack(){
                DeviceImageView(
                    imageName: imageName,
                    fallbackSystemName: device.fallbackSystemName,
                    size: CGSize(width: 56, height: 56)
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
}

struct LogsPageView: View {
    @ObservedObject var viewModel: EarbudsViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                MainWindowCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前连接状态")
                            .font(.headline)

                        Text(viewModel.state.connectionStatus.localizedTitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("最近错误")
                            .font(.headline)

                        Text(viewModel.state.lastError ?? "暂无错误")
                            .font(.callout)
                            .foregroundStyle(viewModel.state.lastError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MainWindowCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("日志列表")
                                .font(.headline)

                            Spacer()

                            Button("复制日志") {
                                copyLogs()
                            }
                            .disabled(viewModel.debugEvents.isEmpty)

                            Button("清空日志") {}
                                .disabled(true)
                        }

                        if viewModel.debugEvents.isEmpty {
                            Text("暂无日志")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(viewModel.debugEvents.enumerated()), id: \.offset) { _, event in
                                    Text(event)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.debugEvents.joined(separator: "\n"), forType: .string)
    }
}

private struct SettingsPageView: View {
    @ObservedObject var viewModel: EarbudsViewModel

    private var devices: [PairedDevice] {
        viewModel.pairedDevices
    }

    var body: some View {
        Form {
            Section("设备") {
                ForEach(devices) { device in
                    DeviceSettingsRow(device: device)
                }
            }

            Section("外观") {
                LabeledContent("主题", value: "跟随系统")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }
}

private struct DeviceSettingsRow: View {
    let device: PairedDevice
    @State private var selectedImageName: String

    init(device: PairedDevice) {
        self.device = device
        _selectedImageName = State(initialValue: device.selectedImageName ?? device.defaultImageName ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DeviceImageView(
                    imageName: selectedImageName.isEmpty ? device.defaultImageName : selectedImageName,
                    fallbackSystemName: device.fallbackSystemName,
                    size: CGSize(width: 44, height: 44)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName)
                        .font(.headline)

                    Text(device.lastConnectedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("蓝牙地址", value: device.modelIdentifier)

            if device.availableImageNames.count > 1 {
                Picker("机身颜色", selection: $selectedImageName) {
                    ForEach(device.availableImageNames, id: \.self) { imageName in
                        Text(DeviceImageProvider.shared.displayTitle(for: imageName))
                            .tag(imageName)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedImageName) { _, imageName in
                    DeviceImageProvider.shared.setSelectedImageName(imageName, for: device.id)
                }
            } else if let imageName = device.defaultImageName {
                LabeledContent("机身颜色", value: DeviceImageProvider.shared.displayTitle(for: imageName))
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MainWindowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
    }
}



private extension View {
    func mainWindowBehavior(title: String) -> some View {
        background(MainWindowConfigurator(title: title))
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView, coordinator: context.coordinator)
        }
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }

        window.delegate = coordinator
        window.title = title
        window.titleVisibility = title.isEmpty ? .hidden : .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .automatic
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.fullScreen)
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.minSize = coordinator.minimumSize
        window.maxSize = coordinator.maximumSize
        window.contentMinSize = coordinator.minimumSize
        window.contentMaxSize = coordinator.maximumSize
        coordinator.clampWindowFrame(window)
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        window.isOpaque = false
        window.backgroundColor = .clear
        window.toolbar?.showsBaselineSeparator = false
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        let minimumSize = NSSize(width: 512, height: 720)
        let maximumSize = NSSize(width: 768, height: 1440)

        func windowShouldZoom(_ sender: NSWindow, toFrame newFrame: NSRect) -> Bool {
            false
        }

        func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
            window.frame
        }

        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            clampedSize(frameSize)
        }

        func windowDidResize(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            clampWindowFrame(window)
        }

        func clampWindowFrame(_ window: NSWindow) {
            let currentFrame = window.frame
            let targetSize = clampedSize(currentFrame.size)

            guard currentFrame.size != targetSize else { return }

            var targetFrame = currentFrame
            let topEdge = targetFrame.maxY
            targetFrame.size = targetSize
            targetFrame.origin.y = topEdge - targetSize.height
            window.setFrame(targetFrame, display: true)
        }

        private func clampedSize(_ size: NSSize) -> NSSize {
            NSSize(
                width: min(max(size.width, minimumSize.width), maximumSize.width),
                height: min(max(size.height, minimumSize.height), maximumSize.height)
            )
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(EarbudsViewModel())
}
