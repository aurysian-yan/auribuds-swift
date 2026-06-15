import Foundation

enum OppoProtocolError: Error, LocalizedError, Equatable {
    case notConnected
    case handshakeFailed
    case batteryDecodeFailed
    case unsupportedANCMode
    case commandInFlight(String)
    case commandBlocked(String)
    case commandTimeout(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "未连接"
        case .handshakeFailed:
            return "握手失败"
        case .batteryDecodeFailed:
            return "电量解析失败"
        case .unsupportedANCMode:
            return "此模式暂未支持"
        case .commandInFlight(let commandName):
            return "\(commandName) 正在执行"
        case .commandBlocked(let reason):
            return reason
        case .commandTimeout(let commandName):
            return "\(commandName) 响应超时"
        }
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case handshaking
    case connected
    case reconnecting
    case error(String)
}

final class OppoProtocol {
    private let backend = OppoProtocolBackend()

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
        try await backend.refreshANC(device: device)
    }

    func setANC(_ mode: ANCMode, deviceName: String) async throws {
        try await backend.setANC(mode, deviceName: deviceName)
    }

    func setANC(_ mode: ANCMode, device: BluetoothDeviceSnapshot) async throws {
        try await backend.setANC(mode, device: device)
    }
}

actor OppoProtocolBackend {
    private let transport = BluetoothHybridTransport()
    private let commandQueue = OppoCommandQueue()
    private var connection: OppoTransportConnection?
    private var connectionState: ConnectionState = .disconnected
    private var connectTask: Task<Void, Error>?
    private var activeDeviceName: String?
    private var activeDevice: BluetoothDeviceSnapshot?
    private var connectedDeviceID: String?
    private var latestBattery = BatteryState.unknown
    private var hasSafeHandshakePassed = false
    private var hasBatteryResponse = false
    private var isRefreshingBattery = false
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
        activeDevice = device
        activeDeviceName = device.name
        try await connectIfNeeded(device: device)

        if latestBattery == .unknown {
            latestBattery = try await requestBattery()
        }

        return latestBattery
    }

    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        closeConnection()
        latestBattery = .unknown
        activeDeviceName = nil
        activeDevice = nil
        connectedDeviceID = nil
        connectionState = .disconnected
        isRefreshingBattery = false
        inFlightCommandName = nil
    }

    func refreshBattery(deviceName: String) async throws -> BatteryState {
        activeDeviceName = deviceName
        try await connectIfNeeded(deviceName: deviceName)
        isRefreshingBattery = true
        defer { isRefreshingBattery = false }

        do {
            let battery = try await requestBattery()
            latestBattery = battery
            return battery
        } catch {
            if isStaleConnectionError(error) {
                try await reconnect(deviceName: deviceName)
                let battery = try await requestBattery()
                latestBattery = battery
                return battery
            }

            throw error
        }
    }

    func refreshBattery(device: BluetoothDeviceSnapshot) async throws -> BatteryState {
        activeDevice = device
        activeDeviceName = device.name
        try await connectIfNeeded(device: device)
        isRefreshingBattery = true
        defer { isRefreshingBattery = false }

        do {
            let battery = try await requestBattery()
            latestBattery = battery
            return battery
        } catch {
            if isStaleConnectionError(error) {
                try await reconnect(device: device)
                let battery = try await requestBattery()
                latestBattery = battery
                return battery
            }

            throw error
        }
    }

    func setANC(_ mode: ANCMode, deviceName: String) async throws {
        activeDeviceName = deviceName
        try await connectIfNeeded(deviceName: deviceName)

        let command: OppoCommand
        switch mode {
        case .off:
            command = OppoCommands.setANCOff
        case .transparency:
            command = OppoCommands.setTransparency
        case .noiseCancellation:
            command = OppoCommands.setNoiseCancellation
        }

        if mode == .noiseCancellation {
            try validateNoiseCancellationGate()
        }

        let startedAt = Date()
        try await send(command)

        if mode == .noiseCancellation {
            let elapsed = Date().timeIntervalSince(startedAt)
            emit(String(format: "setANC(noiseCancellation) completed in %.3fs", elapsed))
        }
    }

    func setANC(_ mode: ANCMode, device: BluetoothDeviceSnapshot) async throws {
        activeDevice = device
        activeDeviceName = device.name
        try await connectIfNeeded(device: device)

        let command: OppoCommand
        switch mode {
        case .off:
            command = OppoCommands.setANCOff
        case .transparency:
            command = OppoCommands.setTransparency
        case .noiseCancellation:
            command = OppoCommands.setNoiseCancellation
        }

        if mode == .noiseCancellation {
            try validateNoiseCancellationGate()
        }

        let startedAt = Date()
        try await send(command)

        if mode == .noiseCancellation {
            let elapsed = Date().timeIntervalSince(startedAt)
            emit(String(format: "setANC(noiseCancellation) completed in %.3fs", elapsed))
        }
    }

    func refreshANC(deviceName: String) async throws -> ANCMode {
        activeDeviceName = deviceName
        try await connectIfNeeded(deviceName: deviceName)

        let responses = try await send(OppoCommands.queryANC)
        for frame in responses {
            if let mode = OppoFrameParser.decodeANCMode(from: frame) {
                return mode
            }
        }

        throw OppoProtocolError.commandTimeout(OppoCommands.queryANC.name)
    }

    func refreshANC(device: BluetoothDeviceSnapshot) async throws -> ANCMode {
        activeDevice = device
        activeDeviceName = device.name
        try await connectIfNeeded(device: device)

        let responses = try await send(OppoCommands.queryANC)
        for frame in responses {
            if let mode = OppoFrameParser.decodeANCMode(from: frame) {
                return mode
            }
        }

        throw OppoProtocolError.commandTimeout(OppoCommands.queryANC.name)
    }

    private func connectIfNeeded(deviceName: String) async throws {
        if let connection, connection.isOpen {
            connectionState = .connected
            return
        }

        if let connectTask {
            try await connectTask.value
            return
        }

        let task = Task {
            try await self.establishConnection(deviceName: deviceName)
        }
        connectTask = task

        do {
            try await task.value
            connectTask = nil
        } catch {
            connectTask = nil
            throw error
        }
    }

    private func connectIfNeeded(device: BluetoothDeviceSnapshot) async throws {
        if let connection, connection.isOpen, connectedDeviceID == device.id {
            connectionState = .connected
            return
        }

        if let connection, connection.isOpen, connectedDeviceID != device.id {
            closeConnection()
        }

        if let connectTask {
            try await connectTask.value
            return
        }

        let task = Task {
            try await self.establishConnection(device: device)
        }
        connectTask = task

        do {
            try await task.value
            connectTask = nil
        } catch {
            connectTask = nil
            throw error
        }
    }

    private func reconnect(deviceName: String) async throws {
        emit("reconnect")
        connectionState = .reconnecting
        closeConnection()
        try await connectIfNeeded(deviceName: deviceName)
    }

    private func reconnect(device: BluetoothDeviceSnapshot) async throws {
        emit("reconnect")
        connectionState = .reconnecting
        closeConnection()
        try await connectIfNeeded(device: device)
    }

    private func establishConnection(deviceName: String) async throws {
        closeConnection()
        connectionState = .connecting
        hasSafeHandshakePassed = false
        hasBatteryResponse = false

        do {
            let connection = try transport.connect(deviceName: deviceName) { [weak self] event in
                Task {
                    await self?.emit(event)
                }
            }

            self.connection = connection
            connectionState = .handshaking
            try await send(OppoCommands.enableStatusPush)
            latestBattery = try await requestBattery()
            connectionState = .connected
            hasSafeHandshakePassed = true
            emit("safe handshake passed")
        } catch {
            closeConnection()
            connectionState = .error(error.localizedDescription)
            throw error
        }
    }

    private func establishConnection(device: BluetoothDeviceSnapshot) async throws {
        closeConnection()
        connectionState = .connecting
        hasSafeHandshakePassed = false
        hasBatteryResponse = false

        do {
            let connection = try transport.connect(device: device) { [weak self] event in
                Task {
                    await self?.emit(event)
                }
            }

            self.connection = connection
            activeDevice = device
            activeDeviceName = device.name
            connectedDeviceID = device.id
            connectionState = .handshaking
            try await send(OppoCommands.enableStatusPush)
            latestBattery = try await requestBattery()
            connectionState = .connected
            hasSafeHandshakePassed = true
            emit("safe handshake passed")
        } catch {
            closeConnection()
            connectionState = .error(error.localizedDescription)
            throw error
        }
    }

    private func requestBattery() async throws -> BatteryState {
        let responses = try await send(OppoCommands.batteryQuery)

        for frame in responses {
            if let battery = OppoFrameParser.decodeBattery(from: frame) {
                hasBatteryResponse = true
                emit("battery \(battery.debugDescription(for: .left))")
                emit("battery \(battery.debugDescription(for: .right))")
                emit("battery \(battery.debugDescription(for: .batteryCase))")
                return battery
            }
        }

        if let lastFrame = responses.last {
            emit("battery decode failed \(lastFrame.hexString)")
        } else {
            emit("battery decode failed")
        }
        throw OppoProtocolError.batteryDecodeFailed
    }

    @discardableResult
    private func send(_ command: OppoCommand) async throws -> [Data] {
        guard let connection, connection.isOpen else {
            throw OppoProtocolError.notConnected
        }

        if let inFlightCommandName {
            throw OppoProtocolError.commandInFlight(inFlightCommandName)
        }

        inFlightCommandName = command.name
        defer { inFlightCommandName = nil }

        return try await commandQueue.execute(
            command,
            connection: connection,
            onEvent: { [weak self] event in
                Task {
                    await self?.emit(event)
                }
            }
        )
    }

    private func closeConnection() {
        connection?.close()
        connection = nil
        connectedDeviceID = nil
        hasSafeHandshakePassed = false
        hasBatteryResponse = false
    }

    private func validateNoiseCancellationGate() throws {
        guard let connection, connection.isOpen else {
            try blockNoiseCancellation("RFCOMM Channel 15 not connected")
            return
        }

        guard hasSafeHandshakePassed else {
            try blockNoiseCancellation("Safe Handshake not passed")
            return
        }

        guard hasBatteryResponse else {
            try blockNoiseCancellation("Battery Response not received")
            return
        }

        if let inFlightCommandName {
            try blockNoiseCancellation("in-flight command \(inFlightCommandName)")
        }

        guard connectionState != .reconnecting else {
            try blockNoiseCancellation("reconnecting")
            return
        }

        guard !isRefreshingBattery else {
            try blockNoiseCancellation("refreshing battery")
            return
        }
    }

    private func blockNoiseCancellation(_ reason: String) throws {
        emit("skip Set Noise Cancellation: \(reason)")
        throw OppoProtocolError.commandBlocked(reason)
    }

    private func isStaleConnectionError(_ error: Error) -> Bool {
        if let error = error as? SafeRfcommError {
            switch error {
            case .writeFailed, .notConnected, .openCompleteFailed, .openCompleteTimeout, .openStartFailed, .channelObjectNil:
                return true
            }
        }

        if let error = error as? BluetoothLETransportError {
            switch error {
            case .notConnected, .writeFailed, .connectionTimeout, .serviceDiscoveryFailed, .characteristicDiscoveryFailed, .writableCharacteristicNotFound:
                return true
            case .bluetoothUnavailable, .deviceNotFound:
                return false
            }
        }

        if let error = error as? OppoProtocolError, error == .notConnected {
            return true
        }

        return false
    }

    private func emit(_ event: String) {
        onEvent?(event)
    }
}

actor OppoCommandQueue {
    func execute(
        _ command: OppoCommand,
        connection: OppoTransportConnection,
        onEvent: @escaping (String) -> Void
    ) async throws -> [Data] {
        var attempt = 0

        while true {
            do {
                let baseline = connection.responseCount
                if command.name == "Set Noise Cancellation" {
                    onEvent("SEND Set Noise Cancellation:")
                    onEvent(command.hexString)
                } else {
                    onEvent("send command \(command.name)")
                    onEvent("send hex \(command.hexString)")
                }
                try connection.write(command)

                let responses = connection.waitForMatchingResponses(
                    since: baseline,
                    timeout: command.timeout,
                    matcher: command.expectedResponse
                )

                if command.name == "Set Noise Cancellation" {
                    for response in responses where OppoFrameParser.isANCCandidateFrame(response) {
                        onEvent("ANC CANDIDATE FRAME:")
                        onEvent(response.hexString)
                    }
                }

                if command.expectedResponse == .none || responses.contains(where: { command.expectedResponse.matches($0) }) {
                    return responses
                }

                throw OppoProtocolError.commandTimeout(command.name)
            } catch {
                guard attempt < command.retryCount else {
                    throw error
                }

                attempt += 1
            }
        }
    }
}
