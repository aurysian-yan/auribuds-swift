import Foundation

enum XiaomiProtocolError: Error, LocalizedError, Equatable {
    case notConnected
    case handshakeFailed
    case batteryDecodeFailed
    case unsupportedANCMode
    case commandInFlight(String)
    case commandRejected(String, UInt8)
    case commandTimeout(String)
    case allTransportsFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "未连接"
        case .handshakeFailed:
            return "小米协议握手失败"
        case .batteryDecodeFailed:
            return "小米电量解析失败"
        case .unsupportedANCMode:
            return "此小米耳机模式暂未支持"
        case .commandInFlight(let commandName):
            return "\(commandName) 正在执行"
        case .commandRejected(let commandName, let status):
            return "\(commandName) 被耳机拒绝：status=0x\(String(format: "%02X", status))"
        case .commandTimeout(let commandName):
            return "\(commandName) 响应超时"
        case .allTransportsFailed(let reason):
            return "小米 BLE/SPP 均连接失败：\(reason)"
        }
    }
}

final class XiaomiProtocol {
    private let backend = XiaomiProtocolBackend()

    var onEvent: ((String) -> Void)? {
        didSet {
            let onEvent = onEvent
            Task {
                await backend.setEventHandler(onEvent)
            }
        }
    }

    func connect(deviceName: String) async throws -> BatteryState {
        try await backend.connect(deviceName: deviceName)
    }

    func connect(device: BluetoothDeviceSnapshot) async throws -> BatteryState {
        try await backend.connect(device: device)
    }

    func disconnect() async {
        await backend.disconnect()
    }

    func refreshBattery(deviceName: String) async throws -> BatteryState {
        try await backend.refreshBattery(deviceName: deviceName)
    }

    func refreshBattery(device: BluetoothDeviceSnapshot) async throws -> BatteryState {
        try await backend.refreshBattery(device: device)
    }

    func refreshANC(deviceName: String) async throws -> ANCMode {
        try await backend.refreshANC(deviceName: deviceName)
    }

    func refreshANC(device: BluetoothDeviceSnapshot) async throws -> ANCMode {
        try await backend.refreshANC(deviceName: device.name)
    }

    func setANC(_ mode: ANCMode, deviceName: String) async throws {
        try await backend.setANC(mode, deviceName: deviceName)
    }

    func setANC(_ mode: ANCMode, device: BluetoothDeviceSnapshot) async throws {
        try await backend.setANC(mode, deviceName: device.name)
    }
}

actor XiaomiProtocolBackend {
    private enum TransportConnection {
        case ble(XiaomiBLEConnection)
        case spp(SafeRfcommConnection)

        var isOpen: Bool {
            switch self {
            case .ble(let connection):
                return connection.isOpen
            case .spp(let connection):
                return connection.isOpen
            }
        }

        var responseCount: Int {
            switch self {
            case .ble(let connection):
                return connection.responseCount
            case .spp(let connection):
                return connection.responseCount
            }
        }

        func write(_ bytes: [UInt8]) throws {
            switch self {
            case .ble(let connection):
                try connection.write(bytes)
            case .spp(let connection):
                try connection.write(bytes)
            }
        }

        func waitForResponses(since baseline: Int, timeout: TimeInterval) -> [Data] {
            switch self {
            case .ble(let connection):
                return connection.waitForResponses(since: baseline, timeout: timeout)
            case .spp(let connection):
                return connection.waitForResponses(since: baseline, timeout: timeout)
            }
        }

        func close() {
            switch self {
            case .ble:
                break
            case .spp(let connection):
                connection.close()
            }
        }
    }

    private let bleTransport = XiaomiBLETransport()
    private let classicTransport = BluetoothClassicTransport(openTimeout: 4, closeTimeout: 1, retryDelay: 0.5, maxAttempts: 1)
    private var connection: TransportConnection?
    private var activeDeviceName: String?
    private var latestBattery = BatteryState.unknown
    private var sequence: UInt8 = 0x10
    private var inFlightCommandName: String?
    private var onEvent: ((String) -> Void)?

    func setEventHandler(_ onEvent: ((String) -> Void)?) {
        self.onEvent = onEvent
    }

    func connect(deviceName: String) async throws -> BatteryState {
        activeDeviceName = deviceName
        try await connectIfNeeded(deviceName: deviceName)

        if latestBattery == .unknown {
            latestBattery = try await requestBattery()
        }

        return latestBattery
    }

    func connect(device: BluetoothDeviceSnapshot) async throws -> BatteryState {
        activeDeviceName = device.name
        try await connectIfNeeded(deviceName: device.name)

        if latestBattery == .unknown {
            latestBattery = try await requestBattery()
        }

        return latestBattery
    }

    func disconnect() {
        connection?.close()
        connection = nil
        bleTransport.disconnect()
        activeDeviceName = nil
        latestBattery = .unknown
        inFlightCommandName = nil
    }

    func refreshBattery(deviceName: String) async throws -> BatteryState {
        activeDeviceName = deviceName
        try await connectIfNeeded(deviceName: deviceName)
        let battery = try await requestBattery()
        latestBattery = battery
        return battery
    }

    func refreshBattery(device: BluetoothDeviceSnapshot) async throws -> BatteryState {
        try await refreshBattery(deviceName: device.name)
    }

    func refreshANC(deviceName: String) async throws -> ANCMode {
        activeDeviceName = deviceName
        try await connectIfNeeded(deviceName: deviceName)
        let command = XiaomiCommands.queryANC(sequence: nextSequence())
        let responses = try await send(command)

        for response in responses {
            if let mode = XiaomiFrameParser.decodeANCMode(from: response) {
                return mode
            }
        }

        throw XiaomiProtocolError.commandTimeout(command.name)
    }

    func setANC(_ mode: ANCMode, deviceName: String) async throws {
        activeDeviceName = deviceName
        try await connectIfNeeded(deviceName: deviceName)
        let command = XiaomiCommands.setANC(mode, sequence: nextSequence())
        try await send(command)
    }

    private func connectIfNeeded(deviceName: String) async throws {
        if let connection, connection.isOpen {
            return
        }

        var failures: [String] = []

        do {
            emit("xiaomi transport BLE preferred")
            let bleConnection = try await bleTransport.connect(deviceName: deviceName, onEvent: { [weak self] event in
                Task { await self?.emit(event) }
            })
            connection = .ble(bleConnection)
            emit("xiaomi transport BLE connected")
            return
        } catch {
            failures.append("BLE: \(error.localizedDescription)")
            emit("xiaomi BLE failed \(error.localizedDescription)")
            bleTransport.disconnect()
        }

        do {
            emit("xiaomi transport SPP fallback")
            let sppConnection = try classicTransport.connect(deviceName: deviceName) { [weak self] event in
                Task { await self?.emit("spp \(event)") }
            }
            connection = .spp(sppConnection)
            emit("xiaomi transport SPP connected")
            return
        } catch {
            failures.append("SPP: \(error.localizedDescription)")
            emit("xiaomi SPP failed \(error.localizedDescription)")
        }

        throw XiaomiProtocolError.allTransportsFailed(failures.joined(separator: "; "))
    }

    private func requestBattery() async throws -> BatteryState {
        let command = XiaomiCommands.getTargetInfo(sequence: nextSequence())
        let responses = try await send(command)

        for response in responses {
            if let battery = XiaomiFrameParser.decodeBattery(from: response) {
                emit("xiaomi battery \(battery.debugDescription(for: .left))")
                emit("xiaomi battery \(battery.debugDescription(for: .right))")
                emit("xiaomi battery \(battery.debugDescription(for: .batteryCase))")
                return battery
            }
        }

        if let lastFrame = responses.last {
            emit("xiaomi battery decode failed \(lastFrame.hexString)")
        } else {
            emit("xiaomi battery decode failed no response")
        }
        throw XiaomiProtocolError.batteryDecodeFailed
    }

    @discardableResult
    private func send(_ command: XiaomiCommand) async throws -> [Data] {
        guard let connection, connection.isOpen else {
            throw XiaomiProtocolError.notConnected
        }

        if let inFlightCommandName {
            throw XiaomiProtocolError.commandInFlight(inFlightCommandName)
        }

        inFlightCommandName = command.name
        defer { inFlightCommandName = nil }

        var attempt = 0
        while true {
            do {
                let baseline = connection.responseCount
                emit("send command \(command.name)")
                emit("send hex \(command.hexString)")
                try connection.write(command.bytes)
                let responses = waitForMatchingResponses(
                    connection: connection,
                    baseline: baseline,
                    timeout: command.timeout,
                    matcher: command.expectedResponse
                )

                if command.expectedResponse == .none || responses.contains(where: { command.expectedResponse.matches($0) }) {
                    return responses
                }

                if let rejectedStatus = responses.compactMap({ command.expectedResponse.rejectedStatus(in: $0) }).first {
                    throw XiaomiProtocolError.commandRejected(command.name, rejectedStatus)
                }

                throw XiaomiProtocolError.commandTimeout(command.name)
            } catch {
                guard attempt < command.retryCount else {
                    throw error
                }
                attempt += 1
                emit("retry command \(command.name) attempt \(attempt)")
            }
        }
    }

    private func waitForMatchingResponses(
        connection: TransportConnection,
        baseline: Int,
        timeout: TimeInterval,
        matcher: XiaomiResponseMatcher
    ) -> [Data] {
        guard matcher != .none else { return [] }
        let deadline = Date().addingTimeInterval(timeout)
        var collected: [Data] = []

        while connection.isOpen && Date() < deadline {
            collected = connection.waitForResponses(since: baseline, timeout: 0.05)
            if collected.contains(where: { matcher.matches($0) }) {
                return collected
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        return connection.waitForResponses(since: baseline, timeout: 0)
    }

    private func nextSequence() -> UInt8 {
        let current = sequence
        sequence = sequence == 0xFF ? 0x10 : sequence &+ 1
        return current
    }

    private func emit(_ event: String) {
        onEvent?(event)
    }
}
