import Foundation

enum OppoProtocolError: Error, LocalizedError {
    case notConnected
    case handshakeFailed
    case batteryDecodeFailed
    case unsupportedANCMode

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected"
        case .handshakeFailed:
            return "Handshake Failed"
        case .batteryDecodeFailed:
            return "Battery Decode Failed"
        case .unsupportedANCMode:
            return "Unsupported ANC mode"
        }
    }
}

final class OppoProtocol {
    private let transport: BluetoothClassicTransport
    private var connection: SafeRfcommConnection?
    private var safeHandshakePassed = false
    private let readTimeout: TimeInterval = 2
    private let ancResponseTimeout: TimeInterval = 2
    var onEvent: ((String) -> Void)?

    init(transport: BluetoothClassicTransport = BluetoothClassicTransport()) {
        self.transport = transport
    }

    func connect(deviceName: String) throws -> BatteryState {
        disconnect()
        safeHandshakePassed = false

        let connection = try transport.connect(deviceName: deviceName) { [weak self] event in
            self?.onEvent?(event)
        }
        self.connection = connection

        let battery = try performSafeHandshake(connection: connection)
        safeHandshakePassed = true
        onEvent?("safe handshake passed")
        return battery
    }

    func disconnect() {
        connection?.close()
        connection = nil
        safeHandshakePassed = false
    }

    func refreshBattery() throws -> BatteryState {
        guard safeHandshakePassed, let connection else {
            throw OppoProtocolError.handshakeFailed
        }

        return try requestBattery(connection: connection)
    }

    func setANC(_ mode: ANCMode) throws {
        guard safeHandshakePassed, let connection else {
            throw OppoProtocolError.handshakeFailed
        }

        let initialQueryBaseline = connection.responseCount
        try send(OppoCommands.queryANC, connection: connection)
        logANCCandidates(connection.waitForResponses(since: initialQueryBaseline, timeout: ancResponseTimeout))

        let command: OppoCommand
        switch mode {
        case .off:
            command = OppoCommands.setANCOff
        case .transparency:
            command = OppoCommands.setTransparency
        case .noiseCancellation:
            throw OppoProtocolError.unsupportedANCMode
        }

        let baseline = connection.responseCount
        try send(command, connection: connection)
        let responses = connection.waitForResponses(since: baseline, timeout: ancResponseTimeout)
        logANCCandidates(responses)

        let queryBaseline = connection.responseCount
        try send(OppoCommands.queryANC, connection: connection)
        let queryResponses = connection.waitForResponses(since: queryBaseline, timeout: ancResponseTimeout)
        logANCCandidates(queryResponses)
    }

    private func performSafeHandshake(connection: SafeRfcommConnection) throws -> BatteryState {
        try send(OppoCommands.enableStatusPush, connection: connection)
        Thread.sleep(forTimeInterval: 0.05)
        return try requestBattery(connection: connection)
    }

    private func requestBattery(connection: SafeRfcommConnection) throws -> BatteryState {
        let baseline = connection.responseCount
        try send(OppoCommands.batteryQuery, connection: connection)
        let responses = connection.waitForResponses(since: baseline, timeout: readTimeout)

        for frame in responses {
            if let battery = OppoFrameParser.decodeBattery(from: frame) {
                return battery
            }
        }

        if let lastFrame = responses.last {
            onEvent?("battery decode failed \(lastFrame.hexString)")
        } else {
            onEvent?("battery decode failed")
        }
        throw OppoProtocolError.batteryDecodeFailed
    }

    private func send(_ command: OppoCommand, connection: SafeRfcommConnection) throws {
        onEvent?("send command \(command.name)")
        onEvent?("send hex \(command.hexString)")
        try connection.write(command)
    }

    private func logANCCandidates(_ responses: [Data]) {
        for frame in responses where OppoFrameParser.isANCCandidateFrame(frame) {
            onEvent?("anc candidate frame \(frame.hexString)")
        }
    }
}
