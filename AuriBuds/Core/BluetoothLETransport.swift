import CoreBluetooth
import Foundation

enum BluetoothLETransportError: Error, LocalizedError {
    case bluetoothUnavailable(String)
    case deviceNotFound(String)
    case connectionTimeout(String)
    case serviceDiscoveryFailed(String)
    case characteristicDiscoveryFailed(String)
    case writableCharacteristicNotFound(String)
    case notConnected
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let reason):
            return "BLE unavailable: \(reason)"
        case .deviceNotFound(let identifier):
            return "No BLE device matched: \(identifier)"
        case .connectionTimeout(let identifier):
            return "BLE connection timed out: \(identifier)"
        case .serviceDiscoveryFailed(let reason):
            return "BLE service discovery failed: \(reason)"
        case .characteristicDiscoveryFailed(let reason):
            return "BLE characteristic discovery failed: \(reason)"
        case .writableCharacteristicNotFound(let name):
            return "No BLE writable characteristic found for: \(name)"
        case .notConnected:
            return "BLE peripheral is not connected"
        case .writeFailed(let reason):
            return "BLE write failed: \(reason)"
        }
    }
}

final class BluetoothLETransport: NSObject {
    private let operationTimeout: TimeInterval = 10
    private let queue = DispatchQueue(label: "AuriBuds.BluetoothLETransport")
    private lazy var central = CBCentralManager(delegate: self, queue: queue)
    private var pendingScan: PendingScan?
    private var pendingConnection: PendingConnection?
    private var activeConnections: [UUID: BluetoothLEConnection] = [:]
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var onEvent: ((String) -> Void)?

    func connect(deviceName: String, onEvent: @escaping (String) -> Void) throws -> BluetoothLEConnection {
        try connect(deviceIdentifier: deviceName, fallbackName: deviceName, onEvent: onEvent)
    }

    func connect(device: BluetoothDeviceSnapshot, onEvent: @escaping (String) -> Void) throws -> BluetoothLEConnection {
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
    ) throws -> BluetoothLEConnection {
        self.onEvent = onEvent
        try waitUntilPoweredOn()
        let peripheral = try scanForPeripheral(matching: deviceIdentifier, fallbackName: fallbackName)
        let session = BluetoothLEConnection(peripheral: peripheral, central: central, queue: queue, onEvent: onEvent)
        try open(session, name: peripheral.name ?? fallbackName)
        return session
    }

    private func waitUntilPoweredOn() throws {
        let deadline = Date().addingTimeInterval(operationTimeout)
        while central.state == .unknown && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        guard central.state == .poweredOn else {
            throw BluetoothLETransportError.bluetoothUnavailable(describe(central.state))
        }
    }

    private func scanForPeripheral(matching identifier: String, fallbackName: String) throws -> CBPeripheral {
        let normalizedTarget = normalize(identifier)
        let semaphore = DispatchSemaphore(value: 0)
        var match: CBPeripheral?

        queue.sync {
            pendingScan = PendingScan(target: normalizedTarget, semaphore: semaphore) { peripheral in
                match = peripheral
            }
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }

        if semaphore.wait(timeout: .now() + operationTimeout) == .timedOut {
            queue.sync {
                central.stopScan()
                pendingScan = nil
            }
        }

        guard let match else {
            throw BluetoothLETransportError.deviceNotFound(identifier.isEmpty ? fallbackName : identifier)
        }

        return match
    }

    private func open(_ connection: BluetoothLEConnection, name: String) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?
        connection.prepareToOpen(semaphore: semaphore) { error in
            failure = error
        }

        queue.sync {
            pendingConnection = PendingConnection(connection: connection, semaphore: semaphore) { error in
                failure = error
            }
            central.connect(connection.peripheral, options: nil)
        }

        if semaphore.wait(timeout: .now() + operationTimeout) == .timedOut {
            queue.sync {
                central.cancelPeripheralConnection(connection.peripheral)
                pendingConnection = nil
            }
            throw BluetoothLETransportError.connectionTimeout(name)
        }

        queue.sync {
            pendingConnection = nil
            if failure == nil {
                activeConnections[connection.peripheral.identifier] = connection
            }
        }

        if let failure { throw failure }
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func describe(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "powered off"
        case .poweredOn: return "powered on"
        @unknown default: return "unknown state"
        }
    }
}

extension BluetoothLETransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onEvent?("BLE state \(describe(central.state))")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        guard let pendingScan else { return }

        let names = [
            peripheral.name,
            advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            peripheral.identifier.uuidString
        ].compactMap { $0 }

        if names.contains(where: { normalize($0).contains(pendingScan.target) || pendingScan.target.contains(normalize($0)) }) {
            central.stopScan()
            self.pendingScan = nil
            onEvent?("BLE discovered \(names.first ?? peripheral.identifier.uuidString)")
            pendingScan.complete(peripheral)
            pendingScan.semaphore.signal()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let pendingConnection, pendingConnection.connection.peripheral === peripheral else { return }
        onEvent?("BLE connected \(peripheral.name ?? peripheral.identifier.uuidString)")
        pendingConnection.connection.didConnect()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let pendingConnection, pendingConnection.connection.peripheral === peripheral else { return }
        self.pendingConnection = nil
        pendingConnection.complete(error ?? BluetoothLETransportError.connectionTimeout(peripheral.name ?? peripheral.identifier.uuidString))
        pendingConnection.semaphore.signal()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let session = activeConnections.removeValue(forKey: peripheral.identifier) ?? pendingConnection?.connection
        session?.handleDisconnect(error: error)
    }
}

private struct PendingScan {
    let target: String
    let semaphore: DispatchSemaphore
    let complete: (CBPeripheral) -> Void
}

private struct PendingConnection {
    let connection: BluetoothLEConnection
    let semaphore: DispatchSemaphore
    let complete: (Error?) -> Void
}

final class BluetoothLEConnection: NSObject, OppoTransportConnection {
    let peripheral: CBPeripheral
    private let central: CBCentralManager
    private let queue: DispatchQueue
    private let onEvent: (String) -> Void
    private let lock = NSLock()
    private var responseStorage: [Data] = []
    private var writableCharacteristic: CBCharacteristic?
    private var notifyCharacteristics: [CBCharacteristic] = []
    private var openSemaphore: DispatchSemaphore?
    private var openCompletion: ((Error?) -> Void)?
    private var openError: Error?
    private(set) var isOpen = false

    var responseCount: Int {
        lock.lock(); defer { lock.unlock() }
        return responseStorage.count
    }

    init(peripheral: CBPeripheral, central: CBCentralManager, queue: DispatchQueue, onEvent: @escaping (String) -> Void) {
        self.peripheral = peripheral
        self.central = central
        self.queue = queue
        self.onEvent = onEvent
        super.init()
        self.peripheral.delegate = self
    }

    func prepareToOpen(semaphore: DispatchSemaphore, completion: @escaping (Error?) -> Void) {
        openSemaphore = semaphore
        openCompletion = completion
        openError = nil
        isOpen = false
    }

    func didConnect() {
        peripheral.discoverServices(nil)
    }

    func handleDisconnect(error: Error?) {
        isOpen = false
        if let error {
            onEvent("BLE disconnected \(error.localizedDescription)")
        } else {
            onEvent("BLE disconnected")
        }
    }

    func write(_ command: OppoCommand) throws { try write(command.bytes) }

    func write(_ bytes: [UInt8]) throws {
        guard isOpen, peripheral.state == .connected else { throw BluetoothLETransportError.notConnected }
        guard let characteristic = writableCharacteristic else {
            throw BluetoothLETransportError.writableCharacteristicNotFound(peripheral.name ?? peripheral.identifier.uuidString)
        }
        let data = Data(bytes)
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        onEvent("BLE write \(data.hexString)")
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    func waitForMatchingResponses(since baseline: Int, timeout: TimeInterval, matcher: OppoResponseMatcher) -> [Data] {
        guard matcher != .none else { return [] }
        let deadline = Date().addingTimeInterval(timeout)
        while isOpen && Date() < deadline {
            let responses = responsesSince(baseline)
            if responses.contains(where: { matcher.matches($0) }) { return responses }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return responsesSince(baseline)
    }

    func waitForResponses(since baseline: Int, timeout: TimeInterval) -> [Data] {
        let deadline = Date().addingTimeInterval(timeout)
        while isOpen && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        return responsesSince(baseline)
    }

    func close() {
        guard isOpen || peripheral.state == .connected else { return }
        isOpen = false
        central.cancelPeripheralConnection(peripheral)
        onEvent("BLE close request")
    }

    private func responsesSince(_ index: Int) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        guard index < responseStorage.count else { return [] }
        return Array(responseStorage[max(0, index)...])
    }

    private func appendResponse(_ data: Data) {
        lock.lock(); responseStorage.append(data); lock.unlock()
        onEvent("BLE recv frame \(data.hexString)")
    }

    private func finishOpenIfReady() {
        guard writableCharacteristic != nil else { return }
        isOpen = true
        onEvent("BLE GATT ready")
        openCompletion?(nil)
        openCompletion = nil
        openSemaphore?.signal()
    }

    private func failOpen(_ error: Error) {
        guard openCompletion != nil else { return }
        openError = error
        isOpen = false
        openCompletion?(error)
        openCompletion = nil
        openSemaphore?.signal()
    }
}

extension BluetoothLEConnection: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            failOpen(BluetoothLETransportError.serviceDiscoveryFailed(error.localizedDescription))
            return
        }

        let services = peripheral.services ?? []
        guard !services.isEmpty else {
            failOpen(BluetoothLETransportError.serviceDiscoveryFailed("no services"))
            return
        }

        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            failOpen(BluetoothLETransportError.characteristicDiscoveryFailed(error.localizedDescription))
            return
        }

        for characteristic in service.characteristics ?? [] {
            if writableCharacteristic == nil,
               characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writableCharacteristic = characteristic
                onEvent("BLE writable characteristic \(characteristic.uuid.uuidString)")
            }

            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                notifyCharacteristics.append(characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
                onEvent("BLE notify characteristic \(characteristic.uuid.uuidString)")
            }
        }

        finishOpenIfReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            onEvent("BLE notify error \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value, !data.isEmpty else { return }
        appendResponse(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            onEvent("BLE write failed \(error.localizedDescription)")
        } else {
            onEvent("BLE write complete")
        }
    }
}
