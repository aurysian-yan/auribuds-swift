import Foundation
import IOBluetooth

final class BluetoothMonitor: NSObject, ObservableObject {
    static let shared = BluetoothMonitor()

    @Published private(set) var lastConnectedDevice: BluetoothDeviceSnapshot?
    @Published private(set) var lastDisconnectedDevice: BluetoothDeviceSnapshot?
    @Published private(set) var availableDevices: [BluetoothDeviceSnapshot] = []

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var isStarted = false

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(handleDeviceConnected(_:device:))
        )

        refreshAvailableDevices()
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil

        for notification in disconnectNotifications.values {
            notification.unregister()
        }

        disconnectNotifications.removeAll()
        isStarted = false
    }

    @objc private func handleDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        registerDisconnectNotification(for: device)
        refreshAvailableDevices()
        publishConnectedSnapshot(for: device)
    }

    @objc private func handleDeviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = normalizedAddress(device.addressString)
        disconnectNotifications[address]?.unregister()
        disconnectNotifications.removeValue(forKey: address)
        refreshAvailableDevices()
        publishDisconnectedSnapshot(for: device)
    }

    func refreshAvailableDevices() {
        let devices = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }

        for device in devices {
            registerDisconnectNotification(for: device)
        }

        let snapshots = devices
            .map { snapshot(for: $0, isConnected: $0.isConnected()) }
            .sorted { first, second in
                first.name.localizedStandardCompare(second.name) == .orderedAscending
            }

        DispatchQueue.main.async { [weak self] in
            self?.availableDevices = snapshots
        }
    }

    private func registerDisconnectNotification(for device: IOBluetoothDevice) {
        let address = normalizedAddress(device.addressString)
        guard !address.isEmpty, disconnectNotifications[address] == nil else { return }

        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(handleDeviceDisconnected(_:device:))
        )
    }

    private func publishConnectedSnapshot(for device: IOBluetoothDevice) {
        publish(snapshot(for: device, isConnected: true)) { [weak self] snapshot in
            self?.lastConnectedDevice = snapshot
        }
    }

    private func publishDisconnectedSnapshot(for device: IOBluetoothDevice) {
        publish(snapshot(for: device, isConnected: false)) { [weak self] snapshot in
            self?.lastDisconnectedDevice = snapshot
        }
    }

    private func publish(_ snapshot: BluetoothDeviceSnapshot, update: @escaping (BluetoothDeviceSnapshot) -> Void) {
        DispatchQueue.main.async {
            update(snapshot)
        }
    }

    private func snapshot(for device: IOBluetoothDevice, isConnected: Bool) -> BluetoothDeviceSnapshot {
        BluetoothDeviceSnapshot(
            name: device.nameOrAddress ?? device.name ?? device.addressString ?? "Bluetooth Device",
            address: normalizedAddress(device.addressString),
            isConnected: isConnected,
            timestamp: Date(),
            majorDeviceClass: UInt32(device.deviceClassMajor),
            minorDeviceClass: UInt32(device.deviceClassMinor)
        )
    }

    private func normalizedAddress(_ address: String?) -> String {
        (address ?? "").uppercased()
    }
}
