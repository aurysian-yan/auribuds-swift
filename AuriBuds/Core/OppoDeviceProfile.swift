import Foundation
import IOBluetooth

struct OppoDeviceProfile: Equatable {
    let channelIDs: [BluetoothRFCOMMChannelID]

    static func profile(for deviceName: String) -> OppoDeviceProfile {
        let normalizedName = normalized(deviceName)

        if normalizedName.contains("air5pro") || normalizedName.contains("encoair5pro") {
            return OppoDeviceProfile(channelIDs: [5, 15])
        }

        return OppoDeviceProfile(channelIDs: [15])
    }

    static func isLikelyOppoAudioDevice(_ deviceName: String) -> Bool {
        let normalizedName = normalized(deviceName)

        return [
            "oppo",
            "oneplus",
            "realme",
            "enco"
        ].contains { normalizedName.contains($0) }
    }

    static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
