import Foundation
import IOBluetooth

enum BluetoothTransportError: Error, LocalizedError {
    case deviceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let name):
            return "No paired Bluetooth device matched: \(name)"
        }
    }
}

final class BluetoothClassicTransport {
    private let channelID: BluetoothRFCOMMChannelID = 15
    private let openTimeout: TimeInterval = 8
    private let closeTimeout: TimeInterval = 3
    private let retryDelay: TimeInterval = 2
    private let maxAttempts = 3

    func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
    }

    func findDevice(named targetName: String) throws -> IOBluetoothDevice {
        let normalizedTarget = normalize(targetName)
        if let device = pairedDevices().first(where: { device in
            normalize(device.name ?? "").contains(normalizedTarget)
                || normalize(device.addressString ?? "").contains(normalizedTarget)
        }) {
            return device
        }

        throw BluetoothTransportError.deviceNotFound(targetName)
    }

    func connect(deviceName: String, onEvent: @escaping (String) -> Void) throws -> SafeRfcommConnection {
        let device = try findDevice(named: deviceName)
        onEvent("device \(device.name ?? deviceName)")

        return try SafeRfcommConnection.connect(
            device: device,
            channelID: channelID,
            maxAttempts: maxAttempts,
            openTimeout: openTimeout,
            closeTimeout: closeTimeout,
            retryDelay: retryDelay,
            onEvent: onEvent
        )
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
