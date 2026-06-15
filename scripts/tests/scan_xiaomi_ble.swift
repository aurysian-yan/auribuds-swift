import CoreBluetooth
import Foundation

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

final class Scanner: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private let deadline = Date().addingTimeInterval(15)
    private var seen: Set<UUID> = []

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("central state: \(central.state.rawValue)")
        guard central.state == .poweredOn else { return }
        print("retrieve AF00 connected: \(central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "0000AF00-0000-1000-8000-00805F9B34FB")]).map { $0.name ?? "unknown" })")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard !seen.contains(peripheral.identifier) else { return }
        seen.insert(peripheral.identifier)
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let overflow = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let solicited = (advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hexString ?? ""
        print("peripheral id=\(peripheral.identifier.uuidString) name=\(peripheral.name ?? "nil") local=\(localName ?? "nil") rssi=\(RSSI) services=\(services) overflow=\(overflow) solicited=\(solicited) mfg=\(manufacturer)")
    }

    func run() {
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        central.stopScan()
        print("scan done, seen \(seen.count)")
    }
}

@main
struct ScanXiaomiBLERunner {
    static func main() {
        let scanner = Scanner()
        scanner.run()
    }
}
