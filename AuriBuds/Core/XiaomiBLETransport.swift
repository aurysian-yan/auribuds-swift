import CoreBluetooth
import Foundation

enum XiaomiBLETransportError: Error, LocalizedError, Equatable {
    case bluetoothUnavailable(String)
    case deviceNotFound(String)
    case connectTimeout(String)
    case serviceNotFound
    case characteristicNotFound
    case writeFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let reason):
            return "Bluetooth LE unavailable: \(reason)"
        case .deviceNotFound(let name):
            return "No Xiaomi BLE peripheral matched: \(name)"
        case .connectTimeout(let name):
            return "BLE connect timed out: \(name)"
        case .serviceNotFound:
            return "Xiaomi BLE service not found"
        case .characteristicNotFound:
            return "Xiaomi BLE write/notify characteristic not found"
        case .writeFailed(let reason):
            return "BLE write failed: \(reason)"
        case .notConnected:
            return "BLE peripheral is not connected"
        }
    }
}

final class XiaomiBLEConnection {
    private let peripheral: CBPeripheral
    private let writeCharacteristic: CBCharacteristic
    private let responseLock = NSLock()
    private var responseStorage: [Data] = []
    private let onEvent: (String) -> Void

    init(
        peripheral: CBPeripheral,
        writeCharacteristic: CBCharacteristic,
        onEvent: @escaping (String) -> Void
    ) {
        self.peripheral = peripheral
        self.writeCharacteristic = writeCharacteristic
        self.onEvent = onEvent
    }

    var responseCount: Int {
        responseLock.lock()
        defer { responseLock.unlock() }
        return responseStorage.count
    }

    var isOpen: Bool {
        peripheral.state == .connected
    }

    func appendResponse(_ data: Data) {
        responseLock.lock()
        responseStorage.append(data)
        responseLock.unlock()
        onEvent("ble recv frame \(data.hexString)")
    }

    func responsesSince(_ index: Int) -> [Data] {
        responseLock.lock()
        defer { responseLock.unlock() }

        let startIndex = max(0, index)
        guard startIndex < responseStorage.count else { return [] }
        return Array(responseStorage[startIndex...])
    }

    func write(_ bytes: [UInt8]) throws {
        guard isOpen else { throw XiaomiBLETransportError.notConnected }
        peripheral.writeValue(Data(bytes), for: writeCharacteristic, type: .withResponse)
        onEvent("ble write queued \(bytes.hexString)")
    }

    func waitForResponses(since baseline: Int, timeout: TimeInterval) -> [Data] {
        let deadline = Date().addingTimeInterval(timeout)

        while isOpen && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        return responsesSince(baseline)
    }
}

final class XiaomiBLETransport: NSObject, @unchecked Sendable {
    private let serviceUUID = CBUUID(string: "0000AF00-0000-1000-8000-00805F9B34FB")
    private let writeUUIDs: Set<CBUUID> = [
        CBUUID(string: "0000AF05-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "0000AF07-0000-1000-8000-00805F9B34FB")
    ]
    private let notifyUUIDs: Set<CBUUID> = [
        CBUUID(string: "0000AF06-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "0000AF08-0000-1000-8000-00805F9B34FB")
    ]

    private var central: CBCentralManager!
    private var stateContinuation: CheckedContinuation<Void, Error>?
    private var connectContinuation: CheckedContinuation<XiaomiBLEConnection, Error>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var targetName = ""
    private var normalizedTargetName = ""
    private var pendingPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var activeConnection: XiaomiBLEConnection?
    private var onEvent: ((String) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func connect(
        deviceName: String,
        timeout: TimeInterval = 10,
        onEvent: @escaping (String) -> Void
    ) async throws -> XiaomiBLEConnection {
        self.onEvent = onEvent
        try await waitUntilPoweredOn(timeout: min(timeout, 4))

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.connectContinuation = continuation
                self.targetName = deviceName
                self.normalizedTargetName = XiaomiDeviceProfile.normalized(deviceName)
                self.writeCharacteristic = nil
                self.activeConnection = nil
                self.emit("ble scan start \(deviceName)")

                let connected = self.central.retrieveConnectedPeripherals(withServices: [self.serviceUUID])
                if let peripheral = connected.first(where: { self.matches($0) }) {
                    self.connect(peripheral)
                } else {
                    self.central.scanForPeripherals(
                        withServices: nil,
                        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                    )
                }

                self.connectTimeoutTask?.cancel()
                self.connectTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    await MainActor.run {
                        self?.completeConnect(.failure(XiaomiBLETransportError.connectTimeout(deviceName)))
                    }
                }
            }
        }
    }

    func disconnect() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        if central.isScanning {
            central.stopScan()
        }
        if let pendingPeripheral, pendingPeripheral.state == .connected || pendingPeripheral.state == .connecting {
            central.cancelPeripheralConnection(pendingPeripheral)
        }
        pendingPeripheral = nil
        writeCharacteristic = nil
        activeConnection = nil
    }

    private func waitUntilPoweredOn(timeout: TimeInterval) async throws {
        switch central.state {
        case .poweredOn:
            return
        case .poweredOff:
            throw XiaomiBLETransportError.bluetoothUnavailable("powered off")
        case .unsupported:
            throw XiaomiBLETransportError.bluetoothUnavailable("unsupported")
        case .unauthorized:
            throw XiaomiBLETransportError.bluetoothUnavailable("unauthorized")
        default:
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.main.async { [weak self] in
                    self?.stateContinuation = continuation
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        await MainActor.run {
                            if let continuation = self?.stateContinuation {
                                self?.stateContinuation = nil
                                continuation.resume(throwing: XiaomiBLETransportError.bluetoothUnavailable("state \(self?.central.state.rawValue ?? -1)"))
                            }
                        }
                    }
                }
            }
        }
    }

    private func matches(_ peripheral: CBPeripheral) -> Bool {
        guard let name = peripheral.name, !normalizedTargetName.isEmpty else { return false }
        let normalizedPeripheralName = XiaomiDeviceProfile.normalized(name)
        return normalizedPeripheralName.contains(normalizedTargetName)
            || normalizedTargetName.contains(normalizedPeripheralName)
            || XiaomiDeviceProfile.isLikelyXiaomiAudioDevice(name)
    }

    private func connect(_ peripheral: CBPeripheral) {
        emit("ble peripheral \(peripheral.name ?? "unknown")")
        if central.isScanning {
            central.stopScan()
        }
        pendingPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    private func completeConnect(_ result: Result<XiaomiBLEConnection, Error>) {
        guard let continuation = connectContinuation else { return }
        connectContinuation = nil
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        if central.isScanning {
            central.stopScan()
        }

        switch result {
        case .success(let connection):
            activeConnection = connection
            continuation.resume(returning: connection)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func emit(_ event: String) {
        onEvent?(event)
    }
}

extension XiaomiBLETransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard let continuation = stateContinuation else { return }

        switch central.state {
        case .poweredOn:
            stateContinuation = nil
            continuation.resume()
        case .poweredOff:
            stateContinuation = nil
            continuation.resume(throwing: XiaomiBLETransportError.bluetoothUnavailable("powered off"))
        case .unsupported:
            stateContinuation = nil
            continuation.resume(throwing: XiaomiBLETransportError.bluetoothUnavailable("unsupported"))
        case .unauthorized:
            stateContinuation = nil
            continuation.resume(throwing: XiaomiBLETransportError.bluetoothUnavailable("unauthorized"))
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard matches(peripheral) else { return }
        emit("ble discovered \(peripheral.name ?? "unknown") rssi=\(RSSI)")
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        emit("ble connected")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        completeConnect(.failure(error ?? XiaomiBLETransportError.deviceNotFound(targetName)))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        emit("ble disconnected")
    }
}

extension XiaomiBLETransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            completeConnect(.failure(error))
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            completeConnect(.failure(XiaomiBLETransportError.serviceNotFound))
            return
        }

        peripheral.discoverCharacteristics(Array(writeUUIDs.union(notifyUUIDs)), for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            completeConnect(.failure(error))
            return
        }

        guard let characteristics = service.characteristics else {
            completeConnect(.failure(XiaomiBLETransportError.characteristicNotFound))
            return
        }

        for characteristic in characteristics {
            if writeUUIDs.contains(characteristic.uuid) {
                writeCharacteristic = characteristic
                emit("ble write characteristic \(characteristic.uuid.uuidString)")
            }

            if notifyUUIDs.contains(characteristic.uuid) {
                peripheral.setNotifyValue(true, for: characteristic)
                emit("ble notify characteristic \(characteristic.uuid.uuidString)")
            }
        }

        guard let writeCharacteristic else {
            completeConnect(.failure(XiaomiBLETransportError.characteristicNotFound))
            return
        }

        let connection = XiaomiBLEConnection(
            peripheral: peripheral,
            writeCharacteristic: writeCharacteristic,
            onEvent: { [weak self] event in self?.emit(event) }
        )
        completeConnect(.success(connection))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            emit("ble notify error \(error.localizedDescription)")
            return
        }

        guard let value = characteristic.value else { return }
        activeConnection?.appendResponse(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            emit("ble write failed \(error.localizedDescription)")
        } else {
            emit("ble write complete")
        }
    }
}
