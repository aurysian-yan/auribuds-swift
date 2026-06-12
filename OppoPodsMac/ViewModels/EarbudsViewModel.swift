import AppKit
import Foundation

@MainActor
final class EarbudsViewModel: ObservableObject {
    @Published private(set) var state = EarbudsState()
    @Published private(set) var debugEvents: [String] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isWritingANC = false

    private let protocolClient = OppoProtocol()
    private var hasStarted = false
    private var autoRefreshTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    var ancMode: ANCMode {
        state.ancMode
    }

    var latestDebugEvent: String? {
        debugEvents.last
    }

    init() {
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

    func reconnect() async {
        guard !isBusy else { return }
        stopAutoRefresh()
        state.connectionStatus = .disconnected
        state.battery = .unknown
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
        isBusy = true

        let client = protocolClient
        let deviceName = state.deviceName

        do {
            let battery = try await client.refreshBattery(deviceName: deviceName)
            state.battery = battery
            state.connectionStatus = .connected
        } catch let error as OppoProtocolError where error == .batteryDecodeFailed {
            state.battery = .unknown
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        } catch {
            stopAutoRefresh()
            state.connectionStatus = .error
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        }

        isBusy = false
    }

    func setANC(_ mode: ANCMode) async {
        guard !isBusy else { return }

        isBusy = true
        isWritingANC = true
        state.lastError = nil
        let client = protocolClient
        let deviceName = state.deviceName

        do {
            try await client.setANC(mode, deviceName: deviceName)
            state.ancMode = mode
            state.connectionStatus = .connected
            startAutoRefresh()
        } catch let error as OppoProtocolError where error == .handshakeFailed {
            state.connectionStatus = .handshakeFailed
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        } catch {
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
        if debugEvents.count > 10 {
            debugEvents.removeFirst(debugEvents.count - 10)
        }
    }

    private func connect(isAutomatic: Bool) async {
        guard !isBusy else { return }
        guard state.connectionStatus != .connecting && state.connectionStatus != .connected else { return }

        isBusy = true
        state.connectionStatus = .connecting
        state.lastError = nil
        appendDebugEvent(isAutomatic ? "auto connect attempt" : "connect attempt")

        let client = protocolClient
        let deviceName = state.deviceName

        do {
            let battery = try await client.connect(deviceName: deviceName)

            state.battery = battery
            state.connectionStatus = .connected
            appendDebugEvent(isAutomatic ? "Auto connect passed" : "connect passed")
            startAutoRefresh()
        } catch let error as OppoProtocolError where error == .batteryDecodeFailed || error == .handshakeFailed {
            state.battery = .unknown
            state.connectionStatus = .handshakeFailed
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        } catch {
            state.connectionStatus = .error
            state.lastError = error.localizedDescription
            appendDebugEvent("error \(error.localizedDescription)")
        }

        isBusy = false
    }

    private func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.refreshBatteryIfNeeded()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
