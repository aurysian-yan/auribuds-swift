import Foundation
import IOBluetooth

private let probeChannels: [BluetoothRFCOMMChannelID] = [12, 13, 15, 17, 29]
private let openTimeout: TimeInterval = 8
private let responseTimeout: TimeInterval = 5
private let closeTimeout: TimeInterval = 3
private let interPacketDelay: TimeInterval = 0.05
private let interChannelDelay: TimeInterval = 1

enum PoCError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case deviceNotFound(String?)

    var description: String {
        switch self {
        case .invalidArgument(let value):
            return "Invalid argument: \(value)"
        case .deviceNotFound(let target):
            if let target {
                return "No paired Bluetooth device matched: \(target)"
            }
            return "No paired OPPO/Enco device was found"
        }
    }
}

struct Options {
    var target: String?
    var listOnly = false
}

struct ProbePacket {
    let name: String
    let source: String
    let raw: [UInt8]
}

struct ProbeResult {
    let channelID: BluetoothRFCOMMChannelID
    let openStatus: IOReturn?
    let responses: [Data]
    let note: String
}

enum OppoProbePackets {
    static let enableStatusPush = ProbePacket(
        name: "Enable Status Push",
        source: "Packets.kt lines 211-214; RfcommController.kt lines 968-971",
        raw: [0xAA, 0x09, 0x00, 0x00, 0x05, 0x02, 0x3A, 0x02, 0x00, 0x01, 0x02]
    )

    static let queryBattery = ProbePacket(
        name: "Battery Query",
        source: "Packets.kt lines 206-209; RfcommController.kt lines 970-974",
        raw: [0xAA, 0x07, 0x00, 0x00, 0x06, 0x01, 0xF0, 0x00, 0x00]
    )

    static let all: [ProbePacket] = [
        enableStatusPush,
        queryBattery
    ]
}

final class ProtocolProbeListener: NSObject {
    private(set) var channel: IOBluetoothRFCOMMChannel?
    private(set) var openStatus: IOReturn?
    private(set) var didClose = false
    private(set) var responses: [Data] = []

    @objc func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        channel = rfcommChannel
        openStatus = status
    }

    @objc func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        didClose = true
    }

    @objc func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        responses.append(data)

        print("RECV:")
        print(data.hexString)
    }

    @objc func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status: IOReturn
    ) {
        print("WRITE COMPLETE:")
        print(formatIOReturn(status))
    }

    @objc func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status: IOReturn,
        bytesWritten: Int
    ) {
        print("WRITE COMPLETE:")
        print(formatIOReturn(status))
        print("BYTES WRITTEN: \(bytesWritten)")
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

func parseOptions() throws -> Options {
    var options = Options()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--name", "--address", "--target":
            guard let value = iterator.next() else {
                throw PoCError.invalidArgument(argument)
            }
            options.target = value
        case "--list":
            options.listOnly = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            if options.target == nil {
                options.target = argument
            } else {
                throw PoCError.invalidArgument(argument)
            }
        }
    }

    return options
}

func printUsage() {
    print("""
    Usage:
      OppoPodsRfcommPoC --name "OPPO Enco Air4 Pro"
      OppoPodsRfcommPoC --address "AA-BB-CC-DD-EE-FF"
      OppoPodsRfcommPoC --list
    """)
}

func pairedDevices() -> [IOBluetoothDevice] {
    (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
}

func printPairedDevices(_ devices: [IOBluetoothDevice]) {
    print("Paired Bluetooth Devices:")
    for device in devices {
        let name = device.name ?? "(unknown)"
        let address = device.addressString ?? "(no address)"
        print("- \(name) [\(address)]")
    }
}

func findTargetDevice(in devices: [IOBluetoothDevice], target: String?) throws -> IOBluetoothDevice {
    if let target {
        let normalizedTarget = normalize(target)
        if let device = devices.first(where: { device in
            normalize(device.name ?? "").contains(normalizedTarget)
                || normalize(device.addressString ?? "").contains(normalizedTarget)
        }) {
            return device
        }
        throw PoCError.deviceNotFound(target)
    }

    if let device = devices.first(where: { device in
        let name = normalize(device.name ?? "")
        return name.contains("oppo")
            || name.contains("enco")
            || name.contains("oneplus")
            || name.contains("realme")
    }) {
        return device
    }

    throw PoCError.deviceNotFound(nil)
}

func normalize(_ value: String) -> String {
    value
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}

func runProbe(device: IOBluetoothDevice, channelID: BluetoothRFCOMMChannelID) -> ProbeResult {
    print("")
    print("CHANNEL \(channelID)")

    let listener = ProtocolProbeListener()
    var openedChannel: IOBluetoothRFCOMMChannel?
    let startStatus = device.openRFCOMMChannelAsync(
        &openedChannel,
        withChannelID: channelID,
        delegate: listener
    )

    guard startStatus == kIOReturnSuccess else {
        print("RESULT:")
        print("open failed: \(formatIOReturn(startStatus))")
        return ProbeResult(channelID: channelID, openStatus: startStatus, responses: [], note: "open start failed")
    }

    let openDeadline = Date().addingTimeInterval(openTimeout)
    while listener.openStatus == nil && !listener.didClose && Date() < openDeadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    guard let openStatus = listener.openStatus else {
        closeIfNeeded(openedChannel ?? listener.channel)
        print("RESULT:")
        print("open timeout")
        return ProbeResult(channelID: channelID, openStatus: nil, responses: [], note: "open complete timeout")
    }

    guard openStatus == kIOReturnSuccess else {
        closeIfNeeded(openedChannel ?? listener.channel)
        print("RESULT:")
        print("open failed: \(formatIOReturn(openStatus))")
        return ProbeResult(channelID: channelID, openStatus: openStatus, responses: [], note: "open complete failed")
    }

    guard let channel = openedChannel ?? listener.channel else {
        print("RESULT:")
        print("open failed: channel object nil")
        return ProbeResult(channelID: channelID, openStatus: openStatus, responses: [], note: "channel object nil")
    }

    for packet in OppoProbePackets.all {
        print("")
        print(packet.name)
        print("Source:")
        print(packet.source)
        print("SEND:")
        print(packet.raw.hexString)

        if !write(packet.raw, to: channel) {
            close(channel: channel, listener: listener)
            return ProbeResult(channelID: channelID, openStatus: openStatus, responses: listener.responses, note: "write failed")
        }

        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: interPacketDelay))
    }

    let responseDeadline = Date().addingTimeInterval(responseTimeout)
    while !listener.didClose && Date() < responseDeadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    let note = listener.responses.isEmpty ? "no response" : "response received"
    print("RESULT:")
    print(note)

    close(channel: channel, listener: listener)

    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: interChannelDelay))

    return ProbeResult(
        channelID: channelID,
        openStatus: openStatus,
        responses: listener.responses,
        note: note
    )
}

func write(_ bytes: [UInt8], to channel: IOBluetoothRFCOMMChannel) -> Bool {
    var mutableBytes = bytes
    let status = mutableBytes.withUnsafeMutableBytes { buffer in
        channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
    }

    guard status == kIOReturnSuccess else {
        print("WRITE FAILED:")
        print(formatIOReturn(status))
        return false
    }

    return true
}

func close(channel: IOBluetoothRFCOMMChannel, listener: ProtocolProbeListener) {
    channel.close()

    let deadline = Date().addingTimeInterval(closeTimeout)
    while !listener.didClose && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
}

func closeIfNeeded(_ channel: IOBluetoothRFCOMMChannel?) {
    guard let channel else { return }
    channel.close()
}

func printRanking(_ results: [ProbeResult]) {
    print("")
    print("Protocol Candidate Ranking")

    let ranked = results.sorted { left, right in
        if left.responses.count == right.responses.count {
            return left.channelID < right.channelID
        }
        return left.responses.count > right.responses.count
    }

    for result in ranked {
        print("")
        print("Channel \(result.channelID)")
        print("response count: \(result.responses.count)")
        print("bytes received: \(result.responses.reduce(0) { $0 + $1.count })")
        print("result: \(result.note)")
    }

    if let best = ranked.first(where: { !$0.responses.isEmpty }) {
        print("")
        print("Most likely OppoPods control channel: \(best.channelID)")
    } else {
        print("")
        print("Most likely OppoPods control channel: none")
    }
}

func run() throws {
    let options = try parseOptions()
    let devices = pairedDevices()
    printPairedDevices(devices)

    if options.listOnly {
        return
    }

    let device = try findTargetDevice(in: devices, target: options.target)
    let deviceName = device.name ?? "OPPO device"
    print("Target Device: \(deviceName)")
    print("Target Address: \(device.addressString ?? "(no address)")")

    let results = probeChannels.map { channelID in
        runProbe(device: device, channelID: channelID)
    }

    printRanking(results)
}

func formatIOReturn(_ value: IOReturn) -> String {
    "0x" + String(UInt32(bitPattern: value), radix: 16, uppercase: true)
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    exit(1)
}
