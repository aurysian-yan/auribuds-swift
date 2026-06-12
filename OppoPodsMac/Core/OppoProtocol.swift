import Foundation

enum OppoProtocolError: Error, LocalizedError, Equatable {
    case notConnected
    case handshakeFailed
    case batteryDecodeFailed
    case unsupportedANCMode
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
        case .commandTimeout(let commandName):
            return "\(commandName) 响应超时"
        }
    }
}

enum ConnectionState {
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

    func disconnect() async {
        await backend.disconnect()
    }

    func refreshBattery(deviceName: String) async throws -> BatteryState {
        try await backend.refreshBattery(deviceName: deviceName)
    }

    func setANC(_ mode: ANCMode, deviceName: String) async throws {
        try await backend.setANC(mode, deviceName: deviceName)
    }
}

actor OppoProtocolBackend {
    private let transport = BluetoothClassicTransport()
    private let commandQueue = OppoCommandQueue()
    private var connection: SafeRfcommConnection?
    private var connectionState: ConnectionState = .disconnected
    private var connectTask: Task<Void, Error>?
    private var activeDeviceName: String?
    private var latestBattery = BatteryState.unknown
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

    func disconnect() {
        closeConnection()
        latestBattery = .unknown
        activeDeviceName = nil
        connectionState = .disconnected
    }

    func refreshBattery(deviceName: String) async throws -> BatteryState {
        activeDeviceName = deviceName
        try await connectIfNeeded(deviceName: deviceName)

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
            throw OppoProtocolError.unsupportedANCMode
        }

        do {
            try await send(command)
        } catch {
            if isStaleConnectionError(error) {
                try await reconnect(deviceName: deviceName)
                try await send(command)
                return
            }

            throw error
        }
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

    private func reconnect(deviceName: String) async throws {
        emit("reconnect")
        connectionState = .reconnecting
        closeConnection()
        try await connectIfNeeded(deviceName: deviceName)
    }

    private func establishConnection(deviceName: String) async throws {
        closeConnection()
        connectionState = .connecting

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
    }

    private func isStaleConnectionError(_ error: Error) -> Bool {
        if let error = error as? SafeRfcommError {
            switch error {
            case .writeFailed, .notConnected, .openCompleteFailed, .openCompleteTimeout, .openStartFailed, .channelObjectNil:
                return true
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
        connection: SafeRfcommConnection,
        onEvent: @escaping (String) -> Void
    ) async throws -> [Data] {
        var attempt = 0

        while true {
            do {
                let baseline = connection.responseCount
                onEvent("send command \(command.name)")
                onEvent("send hex \(command.hexString)")
                try connection.write(command)

                let responses = connection.waitForMatchingResponses(
                    since: baseline,
                    timeout: command.timeout,
                    matcher: command.expectedResponse
                )

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
