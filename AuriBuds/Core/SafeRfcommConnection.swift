import Foundation
import IOBluetooth

enum SafeRfcommError: Error, LocalizedError {
    case openStartFailed(IOReturn)
    case openCompleteTimeout
    case openCompleteFailed(IOReturn)
    case channelObjectNil
    case writeFailed(IOReturn)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .openStartFailed(let status):
            return "RFCOMM open start failed: \(Self.formatIOReturn(status))"
        case .openCompleteTimeout:
            return "RFCOMM open complete timed out"
        case .openCompleteFailed(let status):
            return "RFCOMM open complete failed: \(Self.formatIOReturn(status))"
        case .channelObjectNil:
            return "RFCOMM channel object is nil"
        case .writeFailed(let status):
            return "RFCOMM write failed: \(Self.formatIOReturn(status))"
        case .notConnected:
            return "RFCOMM channel is not connected"
        }
    }

    static func formatIOReturn(_ value: IOReturn) -> String {
        "0x" + String(UInt32(bitPattern: value), radix: 16, uppercase: true)
    }
}

enum TransportState: Equatable {
    case closed
    case opening
    case open
    case closing
}

final class SafeRfcommDelegate: NSObject {
    var channel: IOBluetoothRFCOMMChannel?
    private(set) var openStatus: IOReturn?
    private(set) var didClose = false
    private var responseStorage: [Data] = []
    private let responseLock = NSLock()
    var onEvent: ((String) -> Void)?

    var responseCount: Int {
        responseLock.lock()
        defer { responseLock.unlock() }
        return responseStorage.count
    }

    func responsesSince(_ index: Int) -> [Data] {
        responseLock.lock()
        defer { responseLock.unlock() }

        let startIndex = max(0, index)
        guard startIndex < responseStorage.count else { return [] }
        return Array(responseStorage[startIndex...])
    }

    func resetOpenState() {
        channel = nil
        openStatus = nil
        didClose = false
        responseLock.lock()
        responseStorage.removeAll()
        responseLock.unlock()
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
        onEvent?("channel closed")
    }

    @objc func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        responseLock.lock()
        responseStorage.append(data)
        responseLock.unlock()
        onEvent?("recv frame \(data.hexString)")
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
    private let channel: IOBluetoothRFCOMMChannel
    private let delegate: SafeRfcommDelegate
    private let closeTimeout: TimeInterval
    private(set) var state: TransportState = .open

    var responseCount: Int {
        delegate.responseCount
    }

    var isOpen: Bool {
        state == .open && !delegate.didClose
    }

    init(channel: IOBluetoothRFCOMMChannel, delegate: SafeRfcommDelegate, closeTimeout: TimeInterval) {
        self.channel = channel
        self.delegate = delegate
        self.closeTimeout = closeTimeout
    }

    static func connect(
        device: IOBluetoothDevice,
        channelID: BluetoothRFCOMMChannelID,
        maxAttempts: Int,
        openTimeout: TimeInterval,
        closeTimeout: TimeInterval,
        retryDelay: TimeInterval,
        onEvent: @escaping (String) -> Void
    ) throws -> SafeRfcommConnection {
        for attempt in 1...maxAttempts {
            onEvent("connect attempt \(attempt): channel \(channelID)")
            let delegate = SafeRfcommDelegate()
            delegate.onEvent = onEvent

            do {
                let channel = try openChannel(
                    device: device,
                    channelID: channelID,
                    delegate: delegate,
                    openTimeout: openTimeout,
                    closeTimeout: closeTimeout,
                    onEvent: onEvent
                )
                onEvent("open complete \(SafeRfcommError.formatIOReturn(delegate.openStatus ?? kIOReturnSuccess))")
                return SafeRfcommConnection(channel: channel, delegate: delegate, closeTimeout: closeTimeout)
            } catch SafeRfcommError.openCompleteTimeout {
                onEvent("open timeout")
                delegate.resetAfterFailure()
                Thread.sleep(forTimeInterval: retryDelay)
            } catch {
                onEvent("error \(error.localizedDescription)")
                delegate.resetAfterFailure()
                Thread.sleep(forTimeInterval: retryDelay)
            }
        }

        throw SafeRfcommError.openCompleteTimeout
    }

    func write(_ command: OppoCommand) throws {
        try write(command.bytes)
    }

    func write(_ bytes: [UInt8]) throws {
        guard isOpen else {
            throw SafeRfcommError.notConnected
        }

        var mutableBytes = bytes
        let status = mutableBytes.withUnsafeMutableBytes { buffer in
            channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
        }

        delegate.onEvent?("write complete \(SafeRfcommError.formatIOReturn(status))")

        guard status == kIOReturnSuccess else {
            state = .closed
            throw SafeRfcommError.writeFailed(status)
        }
    }

    func waitForMatchingResponses(
        since baseline: Int,
        timeout: TimeInterval,
        matcher: OppoResponseMatcher
    ) -> [Data] {
        guard matcher != .none else { return [] }

        let deadline = Date().addingTimeInterval(timeout)
        var collected: [Data] = []

        while isOpen && Date() < deadline {
            collected = delegate.responsesSince(baseline)
            if collected.contains(where: { matcher.matches($0) }) {
                return collected
            }

            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        return delegate.responsesSince(baseline)
    }

    func waitForResponses(since baseline: Int, timeout: TimeInterval) -> [Data] {
        let deadline = Date().addingTimeInterval(timeout)

        while isOpen && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        return delegate.responsesSince(baseline)
    }

    func close() {
        guard state != .closed else { return }
        state = .closing
        delegate.resetAfterFailure()
        delegate.channel = channel
        delegate.onEvent?("close request")
        channel.close()

        let deadline = Date().addingTimeInterval(closeTimeout)
        while !delegate.didClose && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if delegate.didClose {
            delegate.onEvent?("channel closed")
        } else {
            delegate.onEvent?("channel closed timeout")
        }
        state = .closed
    }

    private static func openChannel(
        device: IOBluetoothDevice,
        channelID: BluetoothRFCOMMChannelID,
        delegate: SafeRfcommDelegate,
        openTimeout: TimeInterval,
        closeTimeout: TimeInterval,
        onEvent: @escaping (String) -> Void
    ) throws -> IOBluetoothRFCOMMChannel {
        delegate.resetOpenState()
        var openedChannel: IOBluetoothRFCOMMChannel?
        let startStatus = device.openRFCOMMChannelAsync(
            &openedChannel,
            withChannelID: channelID,
            delegate: delegate
        )

        delegate.channel = openedChannel

        guard startStatus == kIOReturnSuccess else {
            throw SafeRfcommError.openStartFailed(startStatus)
        }

        let deadline = Date().addingTimeInterval(openTimeout)
        while delegate.openStatus == nil && !delegate.didClose && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        guard let openStatus = delegate.openStatus else {
            closeIfNeeded(openedChannel ?? delegate.channel, delegate: delegate, closeTimeout: closeTimeout, onEvent: onEvent)
            delegate.resetAfterFailure()
            throw SafeRfcommError.openCompleteTimeout
        }

        guard openStatus == kIOReturnSuccess else {
            closeIfNeeded(openedChannel ?? delegate.channel, delegate: delegate, closeTimeout: closeTimeout, onEvent: onEvent)
            delegate.resetAfterFailure()
            throw SafeRfcommError.openCompleteFailed(openStatus)
        }

        guard let channel = openedChannel ?? delegate.channel else {
            throw SafeRfcommError.channelObjectNil
        }

        return channel
    }

    private static func closeIfNeeded(
        _ channel: IOBluetoothRFCOMMChannel?,
        delegate: SafeRfcommDelegate,
        closeTimeout: TimeInterval,
        onEvent: @escaping (String) -> Void
    ) {
        guard let channel else { return }
        delegate.resetAfterFailure()
        delegate.channel = channel
        onEvent("close request")
        channel.close()

        let deadline = Date().addingTimeInterval(closeTimeout)
        while !delegate.didClose && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if delegate.didClose {
            onEvent("channel closed")
        } else {
            onEvent("channel closed timeout")
        }
    }
}
