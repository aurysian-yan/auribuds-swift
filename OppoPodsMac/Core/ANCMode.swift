import Foundation

enum ANCMode: String, CaseIterable, Equatable {
    case off
    case transparency
    case noiseCancellation

    static let mainModes: [ANCMode] = [
        .off,
        .transparency,
        .noiseCancellation
    ]

    var localizedTitle: String {
        switch self {
        case .off:
            return "关闭"
        case .transparency:
            return "通透模式"
        case .noiseCancellation:
            return "降噪"
        }
    }
}
