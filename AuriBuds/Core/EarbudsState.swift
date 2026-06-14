import Foundation

enum ConnectionStatus: String, Equatable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case handshaking = "Handshaking"
    case connected = "Connected"
    case reconnecting = "Reconnecting"
    case error = "Error"
    case handshakeFailed = "Handshake Failed"

    var localizedTitle: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "连接中"
        case .handshaking:
            return "握手中"
        case .connected:
            return "已连接"
        case .reconnecting:
            return "重连中"
        case .error:
            return "连接失败"
        case .handshakeFailed:
            return "握手失败"
        }
    }
}

struct EarbudsState: Equatable {
    var deviceName = "OPPO Enco Air4 Pro"
    var deviceAddress: String?
    var currentDevice: BluetoothDeviceSnapshot?
    var availableDevices: [BluetoothDeviceSnapshot] = []
    var systemBluetoothConnected = false
    var appConnected = false
    var connectionStatus: ConnectionStatus = .disconnected
    var battery = BatteryState.unknown
    var ancMode: ANCMode = .off
    var lastError: String?
}
