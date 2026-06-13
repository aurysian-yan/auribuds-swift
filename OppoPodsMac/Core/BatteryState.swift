import Foundation

struct ParsedBatteryLevel: Equatable {
    let level: Int?
    let isCharging: Bool
    let rawValue: Int?

    static func parse(rawValue: UInt8?) -> ParsedBatteryLevel {
        guard let rawValue else {
            return ParsedBatteryLevel(level: nil, isCharging: false, rawValue: nil)
        }

        let rawLevel = Int(rawValue & 0x7F)
        let level = (0...100).contains(rawLevel) ? rawLevel : nil

        return ParsedBatteryLevel(
            level: level,
            isCharging: (rawValue & 0x80) != 0,
            rawValue: Int(rawValue)
        )
    }
}

struct BatteryState: Equatable {
    var left: ParsedBatteryLevel
    var right: ParsedBatteryLevel
    var batteryCase: ParsedBatteryLevel

    static let unknown = BatteryState(left: nil, right: nil, batteryCase: nil)

    init(left: UInt8?, right: UInt8?, batteryCase: UInt8?) {
        self.left = ParsedBatteryLevel.parse(rawValue: left)
        self.right = ParsedBatteryLevel.parse(rawValue: right)
        self.batteryCase = ParsedBatteryLevel.parse(rawValue: batteryCase)
    }

    var averageLevel: Int? {
        let values = [left.level, right.level, batteryCase.level].compactMap { $0 }
        guard !values.isEmpty else { return nil }

        let total = values.reduce(0, +)
        return total / values.count
    }

    func text(for component: BatteryComponent) -> String {
        guard let level = parsedLevel(for: component).level else { return "--" }

        return "\(level)%"
    }

    func isCharging(_ component: BatteryComponent) -> Bool {
        parsedLevel(for: component).isCharging
    }

    func debugDescription(for component: BatteryComponent) -> String {
        let parsedLevel = parsedLevel(for: component)
        let rawText = parsedLevel.rawValue.map(String.init) ?? "nil"
        let levelText = parsedLevel.level.map(String.init) ?? "nil"

        return "\(component.debugName) rawValue=\(rawText) level=\(levelText) isCharging=\(parsedLevel.isCharging)"
    }

    private func parsedLevel(for component: BatteryComponent) -> ParsedBatteryLevel {
        switch component {
        case .left:
            return left
        case .right:
            return right
        case .batteryCase:
            return batteryCase
        }
    }
}

enum BatteryComponent {
    case left
    case right
    case batteryCase

    var debugName: String {
        switch self {
        case .left:
            return "left"
        case .right:
            return "right"
        case .batteryCase:
            return "case"
        }
    }
}
