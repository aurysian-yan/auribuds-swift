import Foundation

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message)\n  actual: \(actual)\nexpected: \(expected)\n", stderr)
        exit(1)
    }
}

func expectNotNil<T>(_ value: T?, _ message: String) -> T {
    guard let value else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
    return value
}

@main
struct XiaomiProtocolTestRunner {
    static func main() {
        let getTargetInfo = XiaomiRCSPFrame.encodeCommand(
            opcode: XiaomiRCSPCommand.getTargetInfo,
            sequence: 0x10,
            targetApp: XiaomiRCSPConstants.targetAppEarphone,
            parameter: [0xFF, 0xFF, 0xFF, 0xFF]
        )
        expectEqual(
            getTargetInfo.hexString,
            "FE DC BA C4 02 00 05 10 FF FF FF FF EF",
            "GetTargetInfo RCSP frame should match SDK packet layout"
        )

        let setANC = XiaomiCommands.setANC(.noiseCancellation, sequence: 0x22)
        expectEqual(
            setANC.bytes.hexString,
            "FE DC BA C4 08 00 04 22 02 04 01 EF",
            "Set ANC should use opcode 8 with VendorData type 4 and ANC value 1"
        )

        let transparent = XiaomiCommands.setANC(.transparency, sequence: 0x23)
        expectEqual(
            transparent.bytes.hexString,
            "FE DC BA C4 08 00 04 23 02 04 02 EF",
            "Set transparency should map to Xiaomi ANC value 2"
        )

        let off = XiaomiCommands.setANC(.off, sequence: 0x24)
        expectEqual(
            off.bytes.hexString,
            "FE DC BA C4 08 00 04 24 02 04 00 EF",
            "Set ANC off should map to Xiaomi ANC value 0"
        )

        let batteryFrame = Data([0xFE, 0xDC, 0xBA, 0x04, 0x02, 0x00, 0x05, 0x00, 0x10, 0x40, 0x85, 0x3C, 0xEF])
        let battery = expectNotNil(
            XiaomiFrameParser.decodeBattery(from: batteryFrame),
            "Battery response should decode mulQuantity triplet"
        )
        expectEqual(battery.left.rawValue, 64, "Left battery raw value should decode")
        expectEqual(battery.right.rawValue, 133, "Right battery charging raw value should decode")
        expectEqual(battery.batteryCase.rawValue, 60, "Case battery raw value should decode")
        expectEqual(battery.right.isCharging, true, "Charging bit should be preserved")

        let redmiBuds4TargetInfo = Data([
            0xFE, 0xDC, 0xBA, 0x04, 0x02, 0x00, 0x2F, 0x00, 0x10, 0x05, 0x01, 0x10, 0x34, 0x10, 0x34,
            0x02, 0x02, 0x60, 0x05, 0x03, 0x27, 0x17, 0x50, 0x34, 0x02, 0x04, 0x01, 0x02, 0x05, 0x00,
            0x03, 0x06, 0x10, 0x34, 0x04, 0x07, 0x60, 0x1A, 0x50, 0x02, 0x08, 0x02, 0x02, 0x09, 0x01,
            0x02, 0x0B, 0x01, 0x02, 0x0C, 0x00, 0x02, 0x0D, 0x03, 0xEF
        ])
        let redmiBattery = expectNotNil(
            XiaomiFrameParser.decodeBattery(from: redmiBuds4TargetInfo),
            "Redmi Buds 4 target info should decode mulQuantity TLV"
        )
        expectEqual(redmiBattery.left.rawValue, 96, "Redmi Buds 4 left battery should decode from TLV id 7")
        expectEqual(redmiBattery.right.rawValue, 26, "Redmi Buds 4 right battery should decode from TLV id 7")
        expectEqual(redmiBattery.batteryCase.rawValue, 80, "Redmi Buds 4 case battery should decode from TLV id 7")

        let ancResponse = Data([0xFE, 0xDC, 0xBA, 0x04, 0x08, 0x00, 0x05, 0x00, 0x22, 0x02, 0x04, 0x02, 0xEF])
        expectEqual(
            XiaomiFrameParser.decodeANCMode(from: ancResponse),
            .transparency,
            "ANC response should decode VendorData type 4"
        )

        let ancConfigResponse = Data([0xFE, 0xDC, 0xBA, 0x04, 0xF3, 0x00, 0x07, 0x00, 0x11, 0x04, 0x00, 0x0B, 0x02, 0x01, 0xEF])
        expectEqual(
            XiaomiFrameParser.decodeANCMode(from: ancConfigResponse),
            .transparency,
            "ANC config response should decode config 0x000B state/value"
        )

        print("Xiaomi protocol tests passed")
    }
}
