import Foundation

enum ConnectionStatus: String, Equatable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case error = "Error"
    case handshakeFailed = "Handshake Failed"

    var localizedTitle: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "连接中"
        case .connected:
            return "已连接"
        case .error:
            return "连接失败"
        case .handshakeFailed:
            return "握手失败"
        }
    }
}

struct EarbudsState: Equatable {
    var deviceName = "OPPO Enco Air4 Pro"
    var connectionStatus: ConnectionStatus = .disconnected
    var battery = BatteryState.unknown
    var ancMode: ANCMode = .off
    var lastError: String?
}
