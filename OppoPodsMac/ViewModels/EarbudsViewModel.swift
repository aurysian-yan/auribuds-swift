import AppKit
import Combine
import Foundation

@MainActor
final class EarbudsViewModel: ObservableObject {
    @Published private(set) var state = EarbudsState()
    @Published private(set) var debugEvents: [String] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isWritingANC = false
    @Published private(set) var lastRefreshDate: Date?

    private let protocolClient = OppoProtocol()
    private let knownDeviceAddressesKey = "knownDeviceAddresses"
    private var hasStarted = false
    private var autoRefreshTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var knownDeviceAddresses: Set<String>
    private var lastConnectionPopupDeviceAddress: String?

    var ancMode: ANCMode {
        state.ancMode
    }

    var latestDebugEvent: String? {
        debugEvents.last
    }

    var pairedDevices: [PairedDevice] {
        var snapshots = state.availableDevices

        if let currentDevice = state.currentDevice,
           !snapshots.contains(where: { $0.id == currentDevice.id }) {
            snapshots.insert(currentDevice, at: 0)
        }

        let devices = snapshots.map { snapshot in
            PairedDevice(
                snapshot: snapshot,
                isAppControllable: isTargetDevice(snapshot)
            )
        }

        if devices.isEmpty {
            return [PairedDevice(state: state)]
        }

        return devices
    }

    init() {
        knownDeviceAddresses = Set(UserDefaults.standard.stringArray(forKey: knownDeviceAddressesKey) ?? [])

        protocolClient.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.appendDebugEvent(event)
            }
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stopAutoRefresh()
                await self.protocolClient.disconnect()
            }
        }

        subscribeToBluetoothMonitor()
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        Task {
            await connect(isAutomatic: true)
        }
    }

    func stopAutoConnect() {
        stopAutoRefresh()
        hasStarted = false
    }

    func connect() async {
        await connect(isAutomatic: false)
    }

    func connect(device: PairedDevice) async {
        guard device.isAppControllable else { return }

        guard let snapshot = device.snapshot else {
            await connect(isAutomatic: false)
            return
        }

        stopBackgroundTasks()
        await connect(isAutomatic: false, snapshot: snapshot)
    }

    func reconnect() async {
        guard !isBusy else { return }
        stopBackgroundTasks()
        state.appConnected = false
        state.connectionStatus = .disconnected
        state.battery = .unknown
        state.ancMode = .off
        appendDebugEvent("reconnect")

        let client = protocolClient
        await client.disconnect()

        await connect(isAutomatic: false)
    }

    func refreshBattery() async {
        await refreshBatteryIfNeeded(force: true)
    }

    func refreshBatteryIfNeeded(force: Bool = false) async {
        guard !isBusy else { return }
        guard force || state.connectionStatus == .connected else { return }
        guard !isWritingANC else { return }
        if let currentDevice = state.currentDevice, !isTargetDevice(currentDevice) {
            return
        }
        isBusy = true

        let client = protocolClient
        let currentDevice = state.currentDevice

        do {
            let battery: BatteryState
            if let currentDevice {
                battery = try await client.refreshBattery(device: currentDevice)
            } else {
                battery = try await client.refreshBattery(deviceName: state.deviceName)
            }
            state.battery = battery
            state.connectionStatus = .connected
            state.appConnected = true
            lastRefreshDate = Date()
        } catch let error as OppoProtocolError where error == .batteryDecodeFailed {
            state.battery = .unknown
            ConnectionPopupWindowController.shared.updateBatteryLevel(nil)
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        } catch {
            stopBackgroundTasks()
            state.appConnected = false
            state.connectionStatus = .error
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        }

        isBusy = false
    }

    func setANC(_ mode: ANCMode) async {
        guard !isBusy else { return }
        if let currentDevice = state.currentDevice, !isTargetDevice(currentDevice) {
            return
        }

        isBusy = true
        isWritingANC = true
        state.lastError = nil
        let client = protocolClient
        let currentDevice = state.currentDevice

        do {
            if let currentDevice {
                try await client.setANC(mode, device: currentDevice)
            } else {
                try await client.setANC(mode, deviceName: state.deviceName)
            }
            state.ancMode = mode
            state.connectionStatus = .connected
            state.appConnected = true
            startAutoRefresh()
        } catch let error as OppoProtocolError where error == .handshakeFailed {
            state.appConnected = false
            state.connectionStatus = .handshakeFailed
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        } catch {
            state.appConnected = false
            state.connectionStatus = .error
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        }

        isWritingANC = false
        isBusy = false
    }

    func addDebugLog(_ event: String) {
        appendDebugEvent(event)
    }

    private func appendDebugEvent(_ event: String) {
        debugEvents.append(event)
        if debugEvents.count > 50 {
            debugEvents.removeFirst(debugEvents.count - 50)
        }
    }

    private func subscribeToBluetoothMonitor() {
        BluetoothMonitor.shared.$availableDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshots in
                self?.state.availableDevices = snapshots
            }
            .store(in: &cancellables)

        BluetoothMonitor.shared.$lastConnectedDevice
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                Task { @MainActor in
                    await self?.handleBluetoothConnected(snapshot)
                }
            }
            .store(in: &cancellables)

        BluetoothMonitor.shared.$lastDisconnectedDevice
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                Task { @MainActor in
                    await self?.handleBluetoothDisconnected(snapshot)
                }
            }
            .store(in: &cancellables)
    }

    private func handleBluetoothConnected(_ snapshot: BluetoothDeviceSnapshot) async {
        guard isTargetDevice(snapshot) else { return }

        state.systemBluetoothConnected = true
        state.deviceName = snapshot.name
        state.deviceAddress = snapshot.address
        state.currentDevice = snapshot
        rememberDeviceAddress(snapshot.address)
        appendDebugEvent("system bluetooth connected \(snapshot.name)")
        if lastConnectionPopupDeviceAddress != snapshot.address {
            lastConnectionPopupDeviceAddress = snapshot.address
            ConnectionPopupWindowController.shared.showConnected(
                deviceName: snapshot.name,
                batteryLevel: nil,
                imageName: DeviceImageProvider.shared.primaryImageName(for: snapshot)
            )
        }

        await connect(isAutomatic: true, snapshot: snapshot)
    }

    private func handleBluetoothDisconnected(_ snapshot: BluetoothDeviceSnapshot) async {
        guard isCurrentDevice(snapshot) else { return }

        appendDebugEvent("system bluetooth disconnected \(snapshot.name)")
        if lastConnectionPopupDeviceAddress == snapshot.address {
            lastConnectionPopupDeviceAddress = nil
        }
        ConnectionPopupWindowController.shared.hide()
        stopBackgroundTasks()

        let client = protocolClient
        await client.disconnect()
        markDisconnected()
    }

    private func connect(isAutomatic: Bool, snapshot: BluetoothDeviceSnapshot? = nil) async {
        guard !isBusy else { return }

        if let snapshot, !isTargetDevice(snapshot) {
            return
        }

        if let snapshot,
           state.connectionStatus == .connected,
           state.currentDevice?.id != snapshot.id {
            let client = protocolClient
            await client.disconnect()
            state.connectionStatus = .disconnected
            state.appConnected = false
            state.battery = .unknown
            state.ancMode = .off
        }

        guard state.connectionStatus != .connecting && state.connectionStatus != .connected else { return }

        isBusy = true
        if let snapshot {
            state.systemBluetoothConnected = true
            state.deviceName = snapshot.name
            state.deviceAddress = snapshot.address
            state.currentDevice = snapshot
        }
        state.connectionStatus = .connecting
        state.appConnected = false
        state.lastError = nil
        appendDebugEvent(isAutomatic ? "auto connect attempt" : "connect attempt")

        let client = protocolClient
        let currentDevice = state.currentDevice

        do {
            let battery: BatteryState
            if let currentDevice {
                battery = try await client.connect(device: currentDevice)
            } else {
                battery = try await client.connect(deviceName: state.deviceName)
            }

            state.battery = battery
            state.connectionStatus = .connected
            state.systemBluetoothConnected = true
            state.appConnected = true
            lastRefreshDate = Date()
            if let snapshot {
                rememberDeviceAddress(snapshot.address)
            }
            await refreshANCStatusAfterConnect(device: currentDevice)
            appendDebugEvent(isAutomatic ? "Auto connect passed" : "connect passed")
            startAutoRefresh()
        } catch let error as OppoProtocolError where error == .batteryDecodeFailed || error == .handshakeFailed {
            state.battery = .unknown
            state.appConnected = false
            state.connectionStatus = .handshakeFailed
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        } catch {
            state.appConnected = false
            state.connectionStatus = .error
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        }

        isBusy = false
    }

    private func refreshANCStatusAfterConnect(device: BluetoothDeviceSnapshot?) async {
        if let device, !isTargetDevice(device) {
            return
        }

        do {
            if let device {
                state.ancMode = try await protocolClient.refreshANC(device: device)
            } else {
                state.ancMode = try await protocolClient.refreshANC(deviceName: state.deviceName)
            }
        } catch {
            appendDebugEvent("error \(error.localizedDescription)")
        }
    }

    private func refreshANCIfNeeded() async {
        guard !isBusy else { return }
        guard state.connectionStatus == .connected else { return }
        guard !isWritingANC else { return }
        if let currentDevice = state.currentDevice, !isTargetDevice(currentDevice) {
            return
        }

        do {
            if let currentDevice = state.currentDevice {
                state.ancMode = try await protocolClient.refreshANC(device: currentDevice)
            } else {
                state.ancMode = try await protocolClient.refreshANC(deviceName: state.deviceName)
            }
        } catch {
            appendDebugEvent("error \(error.localizedDescription)")
        }
    }

    private func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.refreshBatteryIfNeeded()
                await self?.refreshANCIfNeeded()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func stopBackgroundTasks() {
        stopAutoRefresh()
    }

    private func markDisconnected() {
        stopBackgroundTasks()
        state.systemBluetoothConnected = false
        state.appConnected = false
        state.connectionStatus = .disconnected
        state.deviceAddress = nil
        state.currentDevice = nil
        state.battery = .unknown
        state.ancMode = .off
        state.lastError = nil
        lastRefreshDate = nil
        isBusy = false
        isWritingANC = false
    }

    private func isTargetDevice(_ snapshot: BluetoothDeviceSnapshot) -> Bool {
        if knownDeviceAddresses.contains(snapshot.address) {
            return true
        }

        return OppoDeviceProfile.isLikelyOppoAudioDevice(snapshot.name)
    }

    private func isCurrentDevice(_ snapshot: BluetoothDeviceSnapshot) -> Bool {
        if let currentAddress = state.currentDevice?.address ?? state.deviceAddress, !currentAddress.isEmpty {
            return currentAddress == snapshot.address
        }

        return !snapshot.name.isEmpty && state.deviceName.caseInsensitiveCompare(snapshot.name) == .orderedSame
    }

    private func rememberDeviceAddress(_ address: String) {
        guard !address.isEmpty else { return }
        knownDeviceAddresses.insert(address)
        UserDefaults.standard.set(Array(knownDeviceAddresses).sorted(), forKey: knownDeviceAddressesKey)
    }
}
