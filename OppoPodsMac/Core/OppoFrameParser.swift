import Foundation

enum OppoFrameParser {
    static func decodeBattery(from data: Data) -> BatteryState? {
        let bytes = Array(data)
        guard bytes.count >= 4 else { return nil }

        for commandIndex in 0...(bytes.count - 3) where bytes[commandIndex] == 0x06 && bytes[commandIndex + 1] == 0x81 && bytes[commandIndex + 2] == 0xF0 {
            guard bytes[..<commandIndex].contains(0xAA) else { continue }

            if let fields = parseBatteryFields(in: bytes, after: commandIndex + 3) {
                return BatteryState(
                    left: normalizedBatteryValue(fields.left),
                    right: normalizedBatteryValue(fields.right),
                    batteryCase: normalizedBatteryValue(fields.batteryCase)
                )
            }

            return .unknown
        }

        return nil
    }

    static func isBatteryResponse(_ data: Data) -> Bool {
        decodeBattery(from: data) != nil
    }

    static func isANCCandidateFrame(_ data: Data) -> Bool {
        let bytes = Array(data)
        guard bytes.count >= 6, bytes.contains(0xAA) else { return false }

        for index in 0..<(bytes.count - 1) {
            if bytes[index] == 0x0C && bytes[index + 1] == 0x81 {
                return true
            }

            if bytes[index] == 0x04 && bytes[index + 1] == 0x02 {
                return true
            }
        }

        return false
    }

    static func isANCResponse(_ data: Data) -> Bool {
        isANCCandidateFrame(data)
    }

    private static func parseBatteryFields(in bytes: [UInt8], after startIndex: Int) -> (left: UInt8, right: UInt8, batteryCase: UInt8)? {
        guard startIndex <= bytes.count - 7 else { return nil }

        for index in startIndex...(bytes.count - 7) where bytes[index] == 0x03 {
            guard bytes[index + 1] == 0x01,
                  bytes[index + 3] == 0x02,
                  bytes[index + 5] == 0x03 else {
                continue
            }

            return (
                left: bytes[index + 2],
                right: bytes[index + 4],
                batteryCase: bytes[index + 6]
            )
        }

        return nil
    }

    private static func normalizedBatteryValue(_ value: UInt8) -> UInt8? {
        guard value != 0x00 && value != 0xFF else { return nil }
        return value
    }
}
