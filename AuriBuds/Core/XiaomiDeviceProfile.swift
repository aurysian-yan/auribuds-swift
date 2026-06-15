import Foundation
import IOBluetooth

struct XiaomiDeviceProfile: Equatable {
    let channelIDs: [BluetoothRFCOMMChannelID]

    static func profile(for deviceName: String) -> XiaomiDeviceProfile {
        XiaomiDeviceProfile(channelIDs: [18, 12, 19, 15])
    }

    static func preferredRFCOMMChannelIDs(for device: IOBluetoothDevice) -> [BluetoothRFCOMMChannelID] {
        let services = (device.services ?? []).compactMap { $0 as? IOBluetoothSDPServiceRecord }
        let rankedChannels = services.compactMap { service -> (rank: Int, channel: BluetoothRFCOMMChannelID)? in
            var channelID: BluetoothRFCOMMChannelID = 0
            guard service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess, channelID > 0 else {
                return nil
            }

            let serviceName = normalized(service.getServiceName() ?? "")
            let rank: Int
            if service.matchesUUID16(0xFD2D) || serviceName.contains("sppgen1") {
                rank = 0
            } else if serviceName.contains("xiaoai") {
                rank = 1
            } else if serviceName.contains("spp1") {
                rank = 2
            } else if service.matchesUUID16(0x1101) {
                rank = 3
            } else {
                rank = 4
            }

            return (rank, channelID)
        }

        return orderedUniqueChannels(rankedChannels.sorted { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.channel < rhs.channel : lhs.rank < rhs.rank
        }.map(\.channel))
    }

    static func isLikelyXiaomiAudioDevice(_ deviceName: String) -> Bool {
        let normalizedName = normalized(deviceName)

        let brandMatched = [
            "xiaomi",
            "redmi",
            "poco",
            "mibuds",
            "miear",
            "xiaomibuds",
            "redmibuds"
        ].contains { normalizedName.contains($0) }

        if brandMatched {
            return true
        }

        return normalizedName.hasPrefix("mi") && ["buds", "earbuds", "air", "truewireless"].contains { normalizedName.contains($0) }
    }

    static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func orderedUniqueChannels(_ channels: [BluetoothRFCOMMChannelID]) -> [BluetoothRFCOMMChannelID] {
        var seen = Set<BluetoothRFCOMMChannelID>()
        return channels.filter { seen.insert($0).inserted }
    }
}
