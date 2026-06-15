import Foundation
import IOBluetooth

@main
struct InspectClassicDevicesRunner {
    static func main() {
        let devices = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
        for device in devices {
            let name = device.name ?? "unknown"
            let address = device.addressString ?? "unknown"
            let connected = device.isConnected()
            print("device name=\(name) address=\(address) connected=\(connected)")
            let services = (device.services ?? []).compactMap { $0 as? IOBluetoothSDPServiceRecord }
            for service in services {
                var channelID: BluetoothRFCOMMChannelID = 0
                let channelResult = service.getRFCOMMChannelID(&channelID)
                let name = service.getServiceName() ?? "unknown"
                let matches = [
                    "FD2D": service.matchesUUID16(0xFD2D),
                    "1101": service.matchesUUID16(0x1101),
                    "0003": service.matchesUUID16(0x0003)
                ]
                print("  service name=\(name) channelResult=\(channelResult) channel=\(channelID) matches=\(matches)")
            }
        }
    }
}
