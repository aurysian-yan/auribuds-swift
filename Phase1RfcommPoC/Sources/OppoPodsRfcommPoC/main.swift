import Foundation
import IOBluetooth

private let controlChannel: BluetoothRFCOMMChannelID = 15
private let candidateChannels: [BluetoothRFCOMMChannelID] = [15, 17, 13, 12, 29]
private let maxControlChannelAttempts = 3
private let openTimeout: TimeInterval = 8
private let readTimeout: TimeInterval = 2
private let closeTimeout: TimeInterval = 3
private let retryDelay: TimeInterval = 2
private let probeHoldDelay: TimeInterval = 2
private let probeChannelDelay: TimeInterval = 1
private let batteryQuerySchedule: [TimeInterval] = [0, 5, 10]

enum PoCError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case deviceNotFound(String?)
    case openStartFailed(IOReturn)
    case openCompleteTimeout
    case openCompleteFailed(IOReturn)
    case channelObjectNil
    case writeFailed(IOReturn)

    var description: String {
        switch self {
        case .invalidArgument(let value):
            return "Invalid argument: \(value)"
        case .deviceNotFound(let target):
            if let target {
                return "No paired Bluetooth device matched: \(target)"
            }
            return "No paired OPPO/Enco device was found"
        case .openStartFailed(let status):
            return "RFCOMM open start failed: \(formatIOReturn(status))"
        case .openCompleteTimeout:
            return "RFCOMM open complete timed out"
        case .openCompleteFailed(let status):
            return "RFCOMM open complete failed: \(formatIOReturn(status))"
        case .channelObjectNil:
            return "RFCOMM channel object is nil"
        case .writeFailed(let status):
            return "RFCOMM write failed: \(formatIOReturn(status))"
        }
    }
}

struct Options {
    var target: String?
    var listOnly = false
}

struct CommandPacket {
    let label: String
    let raw: [UInt8]
}

struct BatterySnapshot {
    let raw: Data
    let left: UInt8?
    let right: UInt8?
    let batteryCase: UInt8?
}

struct SafeHandshakeSummary {
    let channelConnected: Bool
    let handshakePassed: Bool
    let batteryResponseCount: Int
    let batteryResponses: [BatterySnapshot]
}

enum SafeHandshakePackets {
    static let enableStatusPush = CommandPacket(
        label: "Enable Status Push",
        raw: [0xAA, 0x09, 0x00, 0x00, 0x05, 0x02, 0x3A, 0x02, 0x00, 0x01, 0x02]
    )

    static let batteryQuery = CommandPacket(
        label: "Battery Query",
        raw: [0xAA, 0x07, 0x00, 0x00, 0x06, 0x01, 0xF0, 0x00, 0x00]
    )
}

final class SafeRfcommListener: NSObject {
    var channel: IOBluetoothRFCOMMChannel?
    private(set) var openStatus: IOReturn?
    private(set) var didClose = false
    private(set) var responses: [Data] = []

    var responseCount: Int {
        responses.count
    }

    func responsesSince(_ index: Int) -> [Data] {
        guard index < responses.count else { return [] }
        return Array(responses[index...])
    }

    func resetOpenState() {
        channel = nil
        openStatus = nil
        didClose = false
        responses.removeAll()
    }

    func resetAfterFailure() {
        channel = nil
        openStatus = nil
        didClose = false
    }

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
    ) {}

    @objc func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status: IOReturn,
        bytesWritten: Int
    ) {}
}

final class SafeRfcommConnection {
    let listener: SafeRfcommListener
    let channel: IOBluetoothRFCOMMChannel

    init(listener: SafeRfcommListener, channel: IOBluetoothRFCOMMChannel) {
        self.listener = listener
        self.channel = channel
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

func openChannel(
    device: IOBluetoothDevice,
    channelID: BluetoothRFCOMMChannelID,
    listener: SafeRfcommListener
) throws -> IOBluetoothRFCOMMChannel {
    listener.resetOpenState()
    var openedChannel: IOBluetoothRFCOMMChannel?
    let startStatus = device.openRFCOMMChannelAsync(
        &openedChannel,
        withChannelID: channelID,
        delegate: listener
    )

    listener.channel = openedChannel

    guard startStatus == kIOReturnSuccess else {
        throw PoCError.openStartFailed(startStatus)
    }

    let openDeadline = Date().addingTimeInterval(openTimeout)
    while listener.openStatus == nil && !listener.didClose && Date() < openDeadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    guard let openStatus = listener.openStatus else {
        closeIfNeeded(openedChannel ?? listener.channel, listener: listener, shouldLog: true)
        listener.resetAfterFailure()
        throw PoCError.openCompleteTimeout
    }

    guard openStatus == kIOReturnSuccess else {
        closeIfNeeded(openedChannel ?? listener.channel, listener: listener, shouldLog: true)
        listener.resetAfterFailure()
        throw PoCError.openCompleteFailed(openStatus)
    }

    guard let channel = openedChannel ?? listener.channel else {
        throw PoCError.channelObjectNil
    }

    return channel
}

func performReadOnlyStep(_ packet: CommandPacket, channel: IOBluetoothRFCOMMChannel) throws {
    print("")
    print("SEND \(packet.label):")
    print(packet.raw.hexString)
    try write(packet.raw, to: channel)
}

func write(_ bytes: [UInt8], to channel: IOBluetoothRFCOMMChannel) throws {
    var mutableBytes = bytes
    let status = mutableBytes.withUnsafeMutableBytes { buffer in
        channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
    }

    print("WRITE COMPLETE:")
    print(formatIOReturn(status))

    guard status == kIOReturnSuccess else {
        throw PoCError.writeFailed(status)
    }
}

func waitForResponses(listener: SafeRfcommListener, baseline: Int, timeout: TimeInterval) -> [Data] {
    let deadline = Date().addingTimeInterval(timeout)

    while !listener.didClose && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    return listener.responsesSince(baseline)
}

func close(channel: IOBluetoothRFCOMMChannel, listener: SafeRfcommListener) {
    listener.resetAfterFailure()
    listener.channel = channel
    print("")
    print("CLOSE REQUEST")
    channel.close()

    let closeDeadline = Date().addingTimeInterval(closeTimeout)
    while !listener.didClose && Date() < closeDeadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    if listener.didClose {
        print("CHANNEL CLOSED")
    } else {
        print("CHANNEL CLOSED: timeout")
    }
}

func closeIfNeeded(_ channel: IOBluetoothRFCOMMChannel?, listener: SafeRfcommListener, shouldLog: Bool) {
    guard let channel else { return }
    listener.resetAfterFailure()
    listener.channel = channel
    if shouldLog {
        print("")
        print("CLOSE REQUEST")
    }
    channel.close()

    let closeDeadline = Date().addingTimeInterval(closeTimeout)
    while !listener.didClose && Date() < closeDeadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    if shouldLog {
        if listener.didClose {
            print("CHANNEL CLOSED")
        } else {
            print("CHANNEL CLOSED: timeout")
        }
    }
}

func connectControlChannel(device: IOBluetoothDevice) -> SafeRfcommConnection? {
    for attempt in 1...maxControlChannelAttempts {
        print("")
        print("CONNECT ATTEMPT \(attempt): Channel \(controlChannel)")

        let listener = SafeRfcommListener()
        do {
            let channel = try openChannel(device: device, channelID: controlChannel, listener: listener)
            print("OPEN COMPLETE: \(formatIOReturn(listener.openStatus ?? kIOReturnSuccess))")
            print("CONNECTED")
            return SafeRfcommConnection(listener: listener, channel: channel)
        } catch PoCError.openCompleteTimeout {
            print("OPEN COMPLETE: timeout")
            print("TIMEOUT")
            listener.resetAfterFailure()
            Thread.sleep(forTimeInterval: retryDelay)
        } catch {
            if let status = listener.openStatus {
                print("OPEN COMPLETE: \(formatIOReturn(status))")
            } else {
                print("OPEN COMPLETE: unavailable")
            }
            print("TIMEOUT")
            listener.resetAfterFailure()
            Thread.sleep(forTimeInterval: retryDelay)
        }
    }

    probeCandidateChannels(device: device)
    return nil
}

func probeCandidateChannels(device: IOBluetoothDevice) {
    for channelID in candidateChannels {
        print("")
        print("CONNECT ATTEMPT 1: Channel \(channelID)")

        let listener = SafeRfcommListener()
        do {
            let channel = try openChannel(device: device, channelID: channelID, listener: listener)
            print("OPEN COMPLETE: \(formatIOReturn(listener.openStatus ?? kIOReturnSuccess))")
            print("CONNECTED")
            Thread.sleep(forTimeInterval: probeHoldDelay)
            close(channel: channel, listener: listener)
        } catch PoCError.openCompleteTimeout {
            print("OPEN COMPLETE: timeout")
            print("TIMEOUT")
            listener.resetAfterFailure()
        } catch {
            if let status = listener.openStatus {
                print("OPEN COMPLETE: \(formatIOReturn(status))")
            } else {
                print("OPEN COMPLETE: unavailable")
            }
            print("TIMEOUT")
            listener.resetAfterFailure()
        }

        Thread.sleep(forTimeInterval: probeChannelDelay)
    }
}

func runSafeConnectMode(device: IOBluetoothDevice) throws -> SafeHandshakeSummary {
    guard let connection = connectControlChannel(device: device) else {
        print("")
        print("RESULT:")
        print("FAILED")
        return SafeHandshakeSummary(
            channelConnected: false,
            handshakePassed: false,
            batteryResponseCount: 0,
            batteryResponses: []
        )
    }

    defer {
        close(channel: connection.channel, listener: connection.listener)
    }

    try performReadOnlyStep(SafeHandshakePackets.enableStatusPush, channel: connection.channel)
    Thread.sleep(forTimeInterval: 0.05)

    let queryStart = Date()
    var batteryResponses: [BatterySnapshot] = []
    var batteryResponseCount = 0

    for (index, scheduledDelay) in batteryQuerySchedule.enumerated() {
        let targetDate = queryStart.addingTimeInterval(scheduledDelay)
        while Date() < targetDate {
            RunLoop.current.run(mode: .default, before: min(targetDate, Date(timeIntervalSinceNow: 0.05)))
        }

        let queryNumber = index + 1
        print("")
        print("BATTERY QUERY #\(queryNumber)")
        print("SEND:")
        print(SafeHandshakePackets.batteryQuery.raw.hexString)

        let baseline = connection.listener.responseCount
        try write(SafeHandshakePackets.batteryQuery.raw, to: connection.channel)
        let responses = waitForResponses(listener: connection.listener, baseline: baseline, timeout: readTimeout)
        let decodedResponses = responses.compactMap { batterySnapshot(from: $0) }

        if decodedResponses.isEmpty {
            print("")
            print("BATTERY RAW:")
            print("none")
            print("")
            print("BATTERY DECODE:")
            print("Left: Unknown / Not present / Not reported")
            print("Right: Unknown / Not present / Not reported")
            print("Case: Unknown / Not present / Not reported")
        } else {
            batteryResponseCount += 1
            for snapshot in decodedResponses {
                printBatterySnapshot(snapshot)
                batteryResponses.append(snapshot)
            }
        }
    }

    let passed = batteryResponseCount > 0

    print("")
    print("RESULT:")
    if passed {
        print("SAFE HANDSHAKE PASSED")
    } else {
        print("FAILED")
    }

    return SafeHandshakeSummary(
        channelConnected: true,
        handshakePassed: passed,
        batteryResponseCount: batteryResponseCount,
        batteryResponses: batteryResponses
    )
}

func batterySnapshot(from data: Data) -> BatterySnapshot? {
    let bytes = Array(data)
    guard bytes.count >= 4 else { return nil }

    for commandIndex in 0...(bytes.count - 3) where bytes[commandIndex] == 0x06 && bytes[commandIndex + 1] == 0x81 && bytes[commandIndex + 2] == 0xF0 {
        guard bytes[..<commandIndex].contains(0xAA) else { continue }

        if let fields = parseBatteryFields(in: bytes, after: commandIndex + 3) {
            return BatterySnapshot(
                raw: data,
                left: normalizedBatteryValue(fields.left),
                right: normalizedBatteryValue(fields.right),
                batteryCase: normalizedBatteryValue(fields.batteryCase)
            )
        }

        return BatterySnapshot(raw: data, left: nil, right: nil, batteryCase: nil)
    }

    return nil
}

func parseBatteryFields(in bytes: [UInt8], after startIndex: Int) -> (left: UInt8, right: UInt8, batteryCase: UInt8)? {
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

func normalizedBatteryValue(_ value: UInt8) -> UInt8? {
    guard value != 0x00 && value != 0xFF else { return nil }
    return value
}

func printBatterySnapshot(_ snapshot: BatterySnapshot) {
    print("")
    print("BATTERY RAW:")
    print(snapshot.raw.hexString)
    print("")
    print("BATTERY DECODE:")
    print("Left: \(batteryText(snapshot.left))")
    print("Right: \(batteryText(snapshot.right))")
    print("Case: \(batteryText(snapshot.batteryCase))")
}

func batteryText(_ value: UInt8?) -> String {
    guard let value else {
        return "Unknown / Not present / Not reported"
    }

    return "\(value)%"
}

func printSummary(_ summary: SafeHandshakeSummary) {
    let latestBattery = summary.batteryResponses.last

    print("")
    print("SUMMARY:")
    print("Channel 15 connect: \(summary.channelConnected ? "success" : "failed")")
    print("Safe handshake: \(summary.handshakePassed ? "passed" : "failed")")
    print("Battery responses: \(summary.batteryResponseCount) / \(batteryQuerySchedule.count)")
    print("Decoded battery:")
    print("* Left: \(batteryText(latestBattery?.left))")
    print("* Right: \(batteryText(latestBattery?.right))")
    print("* Case: \(batteryText(latestBattery?.batteryCase))")

    if hasPossibleFieldMismatch(summary.batteryResponses) {
        print("")
        print("POSSIBLE FIELD MISMATCH")
    }
}

func hasPossibleFieldMismatch(_ responses: [BatterySnapshot]) -> Bool {
    responses.contains { snapshot in
        [snapshot.left, snapshot.right, snapshot.batteryCase].contains { value in
            guard let value else { return false }
            return value > 100
        }
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

    let summary = try runSafeConnectMode(device: device)
    printSummary(summary)
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
