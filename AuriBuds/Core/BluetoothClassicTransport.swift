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
    private let openTimeout: TimeInterval = 8
    private let closeTimeout: TimeInterval = 3
    private let retryDelay: TimeInterval = 2
    private let maxAttempts = 3
    private var cachedDevice: IOBluetoothDevice?
    private var cachedDeviceIdentifier: String?

    func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
    }

    func findDevice(named targetName: String) throws -> IOBluetoothDevice {
        try findDevice(identifier: targetName)
    }

    func findDevice(identifier: String) throws -> IOBluetoothDevice {
        if let cachedDevice,
           let cachedDeviceIdentifier,
           normalize(cachedDeviceIdentifier) == normalize(identifier) {
            return cachedDevice
        }

        let normalizedTarget = normalize(identifier)
        if let device = pairedDevices().first(where: { device in
            normalize(device.name ?? "").contains(normalizedTarget)
                || normalize(device.addressString ?? "").contains(normalizedTarget)
        }) {
            cachedDevice = device
            cachedDeviceIdentifier = identifier
            return device
        }

        throw BluetoothTransportError.deviceNotFound(identifier)
    }

    func connect(deviceName: String, onEvent: @escaping (String) -> Void) throws -> SafeRfcommConnection {
        try connect(deviceIdentifier: deviceName, fallbackName: deviceName, onEvent: onEvent)
    }

    func connect(device: BluetoothDeviceSnapshot, onEvent: @escaping (String) -> Void) throws -> SafeRfcommConnection {
        try connect(
            deviceIdentifier: device.address.isEmpty ? device.name : device.address,
            fallbackName: device.name,
            onEvent: onEvent
        )
    }

    private func connect(
        deviceIdentifier: String,
        fallbackName: String,
        onEvent: @escaping (String) -> Void
    ) throws -> SafeRfcommConnection {
        let device = try findDevice(identifier: deviceIdentifier)
        let deviceName = device.name ?? fallbackName
        let profile = HeadphoneAdapterRegistry.shared.profile(for: deviceName)
        var lastError: Error?

        onEvent("device \(deviceName)")

        for channelID in profile.rfcommChannelIDs {
            do {
                return try SafeRfcommConnection.connect(
                    device: device,
                    channelID: channelID,
                    maxAttempts: maxAttempts,
                    openTimeout: openTimeout,
                    closeTimeout: closeTimeout,
                    retryDelay: retryDelay,
                    onEvent: onEvent
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? BluetoothTransportError.deviceNotFound(deviceIdentifier)
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
