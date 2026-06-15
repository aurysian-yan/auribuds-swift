import Foundation

enum BluetoothConnectionMode: String, CaseIterable {
    case classic = "Classic RFCOMM"
    case ble = "BLE GATT"
}

final class BluetoothHybridTransport {
    private let classicTransport = BluetoothClassicTransport()
    private let bleTransport = BluetoothLETransport()

    func connect(deviceName: String, onEvent: @escaping (String) -> Void) throws -> OppoTransportConnection {
        try connect(preferredName: deviceName, snapshot: nil, onEvent: onEvent)
    }

    func connect(device: BluetoothDeviceSnapshot, onEvent: @escaping (String) -> Void) throws -> OppoTransportConnection {
        try connect(preferredName: device.name, snapshot: device, onEvent: onEvent)
    }

    private func connect(
        preferredName: String,
        snapshot: BluetoothDeviceSnapshot?,
        onEvent: @escaping (String) -> Void
    ) throws -> OppoTransportConnection {
        var failures: [Error] = []

        do {
            onEvent("transport try Classic RFCOMM")
            if let snapshot {
                return try classicTransport.connect(device: snapshot, onEvent: onEvent)
            }
            return try classicTransport.connect(deviceName: preferredName, onEvent: onEvent)
        } catch {
            failures.append(error)
            onEvent("transport Classic RFCOMM failed: \(error.localizedDescription)")
        }

        do {
            onEvent("transport try BLE GATT")
            if let snapshot {
                return try bleTransport.connect(device: snapshot, onEvent: onEvent)
            }
            return try bleTransport.connect(deviceName: preferredName, onEvent: onEvent)
        } catch {
            failures.append(error)
            onEvent("transport BLE GATT failed: \(error.localizedDescription)")
        }

        throw failures.last ?? BluetoothTransportError.deviceNotFound(preferredName)
    }
}
