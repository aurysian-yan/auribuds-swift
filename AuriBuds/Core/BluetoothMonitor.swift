import CoreBluetooth
import Foundation
import IOBluetooth

final class BluetoothMonitor: NSObject, ObservableObject {
    static let shared = BluetoothMonitor()

    @Published private(set) var lastConnectedDevice: BluetoothDeviceSnapshot?
    @Published private(set) var lastDisconnectedDevice: BluetoothDeviceSnapshot?
    @Published private(set) var availableDevices: [BluetoothDeviceSnapshot] = []

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private lazy var bleCentral = CBCentralManager(delegate: self, queue: nil)
    private var bleSnapshots: [String: BluetoothDeviceSnapshot] = [:]
    private var classicSnapshots: [String: BluetoothDeviceSnapshot] = [:]
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
        startBLEScanIfPossible()
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil

        for notification in disconnectNotifications.values {
            notification.unregister()
        }

        disconnectNotifications.removeAll()
        bleCentral.stopScan()
        bleSnapshots.removeAll()
        classicSnapshots.removeAll()
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

        classicSnapshots = Dictionary(
            uniqueKeysWithValues: devices.map { device in
                let snapshot = snapshot(for: device, isConnected: device.isConnected())
                return (snapshot.id, snapshot)
            }
        )

        publishAvailableDevices()
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

    private func publishAvailableDevices() {
        let snapshots = Array((classicSnapshots.merging(bleSnapshots) { classic, _ in classic }).values)
            .sorted { first, second in
                first.name.localizedStandardCompare(second.name) == .orderedAscending
            }

        DispatchQueue.main.async { [weak self] in
            self?.availableDevices = snapshots
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

    private func startBLEScanIfPossible() {
        guard isStarted, bleCentral.state == .poweredOn, !bleCentral.isScanning else { return }
        bleCentral.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func snapshot(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> BluetoothDeviceSnapshot {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        return BluetoothDeviceSnapshot(
            name: advertisedName ?? peripheral.name ?? "BLE Device",
            address: peripheral.identifier.uuidString.uppercased(),
            isConnected: peripheral.state == .connected,
            timestamp: Date(),
            majorDeviceClass: 4,
            minorDeviceClass: 1
        )
    }

    private func normalizedAddress(_ address: String?) -> String {
        (address ?? "").uppercased()
    }
}

extension BluetoothMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startBLEScanIfPossible()
        } else {
            bleSnapshots.removeAll()
            publishAvailableDevices()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let snapshot = snapshot(for: peripheral, advertisementData: advertisementData)
        guard HeadphoneAdapterRegistry.shared.canControl(snapshot) else { return }
        bleSnapshots[snapshot.id] = snapshot
        publishAvailableDevices()
    }
}
