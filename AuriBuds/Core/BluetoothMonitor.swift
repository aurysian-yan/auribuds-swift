import Combine
import CoreBluetooth
import Foundation
#if os(macOS)
import IOBluetooth
#endif

@MainActor
final class BluetoothMonitor: NSObject, ObservableObject {
    static let shared = BluetoothMonitor()
    private static let xiaomiServiceUUID = CBUUID(string: "0000AF00-0000-1000-8000-00805F9B34FB")

    @Published private(set) var lastConnectedDevice: BluetoothDeviceSnapshot?
    @Published private(set) var lastDisconnectedDevice: BluetoothDeviceSnapshot?
    @Published private(set) var availableDevices: [BluetoothDeviceSnapshot] = []
    @Published private(set) var isScanning = false

#if os(macOS)
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var classicSnapshots: [String: BluetoothDeviceSnapshot] = [:]
#endif
    private lazy var bleCentral = CBCentralManager(delegate: self, queue: nil)
    private var bleSnapshots: [String: BluetoothDeviceSnapshot] = [:]
    private var isStarted = false

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

#if os(macOS)
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(handleDeviceConnected(_:device:))
        )

        refreshAvailableDevices()
#endif
        startBLEScanIfPossible()
    }

    func stop() {
#if os(macOS)
        connectNotification?.unregister()
        connectNotification = nil

        for notification in disconnectNotifications.values {
            notification.unregister()
        }

        disconnectNotifications.removeAll()
        classicSnapshots.removeAll()
#endif
        stopBLEScan()
        bleSnapshots.removeAll()
        isStarted = false
    }

#if os(macOS)
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
#endif

    private func publishAvailableDevices() {
        var allSnapshots = bleSnapshots
#if os(macOS)
        allSnapshots = classicSnapshots.merging(bleSnapshots) { classic, _ in classic }
#endif
        let snapshots = Array(allSnapshots.values)
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

#if os(macOS)
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
#endif

    func rescan() {
        stopBLEScan()
        startBLEScanIfPossible()
    }

    private func startBLEScanIfPossible() {
        guard isStarted, bleCentral.state == .poweredOn, !bleCentral.isScanning else {
            isScanning = bleCentral.isScanning
            return
        }
        refreshConnectedBLEDevices()
        bleCentral.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
    }

    private func stopBLEScan() {
        bleCentral.stopScan()
        isScanning = false
    }

    private func refreshConnectedBLEDevices() {
        let connectedXiaomiDevices = bleCentral.retrieveConnectedPeripherals(
            withServices: [Self.xiaomiServiceUUID]
        )

        for peripheral in connectedXiaomiDevices {
            guard let name = peripheral.name,
                  XiaomiDeviceProfile.isLikelyXiaomiAudioDevice(name) else { continue }

            let snapshot = snapshot(for: peripheral, name: name, isConnected: true)
            bleSnapshots[snapshot.id] = snapshot
        }

        publishAvailableDevices()
    }

    private func snapshot(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> BluetoothDeviceSnapshot {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        return snapshot(
            for: peripheral,
            name: advertisedName ?? peripheral.name ?? "BLE Device",
            isConnected: peripheral.state == .connected
        )
    }

    private func snapshot(for peripheral: CBPeripheral, name: String, isConnected: Bool) -> BluetoothDeviceSnapshot {
        return BluetoothDeviceSnapshot(
            name: name,
            address: peripheral.identifier.uuidString.uppercased(),
            isConnected: isConnected,
            timestamp: Date(),
            majorDeviceClass: 4,
            minorDeviceClass: 1
        )
    }

    private func isSupportedBLEDevice(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? ""

        if OppoDeviceProfile.isLikelyOppoAudioDevice(name) {
            return true
        }

        guard XiaomiDeviceProfile.isLikelyXiaomiAudioDevice(name) else { return false }
        return advertisedServiceUUIDs(from: advertisementData).contains(Self.xiaomiServiceUUID)
    }

    private func advertisedServiceUUIDs(from advertisementData: [String: Any]) -> [CBUUID] {
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflowServiceUUIDs = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        return serviceUUIDs + overflowServiceUUIDs
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
            isScanning = false
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
        guard isSupportedBLEDevice(peripheral: peripheral, advertisementData: advertisementData) else { return }
        let snapshot = snapshot(for: peripheral, advertisementData: advertisementData)
        bleSnapshots[snapshot.id] = snapshot
        publishAvailableDevices()
    }
}
