import Foundation

struct OppoCommand {
    let name: String
    let sources: [String]
    let bytes: [UInt8]
    let expectedResponse: OppoResponseMatcher
    let timeout: TimeInterval
    let retryCount: Int

    init(
        name: String,
        sources: [String],
        bytes: [UInt8],
        expectedResponse: OppoResponseMatcher = .none,
        timeout: TimeInterval = 1,
        retryCount: Int = 0
    ) {
        self.name = name
        self.sources = sources
        self.bytes = bytes
        self.expectedResponse = expectedResponse
        self.timeout = timeout
        self.retryCount = retryCount
    }

    var hexString: String {
        bytes.hexString
    }
}

enum OppoResponseMatcher: Equatable {
    case none
    case battery
    case anc
    case ancMode(UInt8)

    func matches(_ data: Data) -> Bool {
        switch self {
        case .none:
            return true
        case .battery:
            return OppoFrameParser.isBatteryResponse(data)
        case .anc:
            return OppoFrameParser.isANCResponse(data)
        case .ancMode(let modeValue):
            return OppoFrameParser.isANCModeResponse(data, modeValue: modeValue)
        }
    }
}

enum OppoCommands {
    static let enableStatusPush = OppoCommand(
        name: "Enable Status Push",
        sources: [
            "Packets.kt lines 211-214"
        ],
        bytes: [0xAA, 0x09, 0x00, 0x00, 0x05, 0x02, 0x3A, 0x02, 0x00, 0x01, 0x02],
        timeout: 0.2
    )

    static let batteryQuery = OppoCommand(
        name: "Battery Query",
        sources: [
            "Packets.kt lines 206-209",
            "RfcommController.kt lines 981-984",
            "RfcommController.kt lines 996-1002"
        ],
        bytes: [0xAA, 0x07, 0x00, 0x00, 0x06, 0x01, 0xF0, 0x00, 0x00],
        expectedResponse: .battery,
        timeout: 2,
        retryCount: 1
    )

    static let queryANC = OppoCommand(
        name: "Query ANC",
        sources: [
            "Packets.kt lines 12-28",
            "Packets.kt lines 216-219",
            "RfcommController.kt lines 996-1002"
        ],
        bytes: buildPacket(command: 0x010C, payload: [0x01, 0x01]),
        expectedResponse: .anc,
        timeout: 2
    )

    static let setTransparency = OppoCommand(
        name: "Set Transparency",
        sources: [
            "Packets.kt lines 12-28",
            "Packets.kt lines 177-180",
            "RfcommController.kt lines 959-975"
        ],
        bytes: buildPacket(command: 0x0404, payload: [0x01, 0x01, 0x04]),
        expectedResponse: .anc,
        timeout: 2
    )

    static let setANCOff = OppoCommand(
        name: "Set ANC Off",
        sources: [
            "Packets.kt lines 12-28",
            "Packets.kt lines 196-199",
            "RfcommController.kt lines 959-975"
        ],
        bytes: buildPacket(command: 0x0404, payload: [0x01, 0x01, 0x01]),
        expectedResponse: .anc,
        timeout: 2
    )

    static let setNoiseCancellation = OppoCommand(
        name: "Set Noise Cancellation",
        sources: [
            "Packets.kt lines 12-28",
            "Packets.kt lines 32-39",
            "Packets.kt lines 152-155",
            "RfcommController.kt lines 959-975"
        ],
        bytes: buildPacket(command: 0x0404, payload: [0x01, 0x01, 0x02]),
        expectedResponse: .ancMode(0x02),
        timeout: 1.5
    )

    private static func buildPacket(command: UInt16, sequence: UInt8 = 0xF0, payload: [UInt8] = []) -> [UInt8] {
        let payloadLength = UInt16(payload.count)
        let totalLength = UInt8(7 + payload.count)
        return [
            0xAA,
            totalLength,
            0x00,
            0x00,
            UInt8(command & 0x00FF),
            UInt8((command >> 8) & 0x00FF),
            sequence,
            UInt8(payloadLength & 0x00FF),
            UInt8((payloadLength >> 8) & 0x00FF)
        ] + payload
    }
}

extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
