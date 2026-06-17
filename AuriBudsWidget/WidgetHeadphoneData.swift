import Foundation

struct WidgetHeadphoneData: Codable {
    let deviceName: String
    let connectionStatus: String
    let batteryLeft: String
    let batteryRight: String
    let batteryCase: String
    let ancMode: String

    static let appGroupSuite = "group.top.aurysian.auribuds"
    private static let storageKey = "widgetHeadphoneData"

    func save() {
        guard let data = try? JSONEncoder().encode(self),
              let store = UserDefaults(suiteName: Self.appGroupSuite) else { return }
        store.set(data, forKey: Self.storageKey)
    }

    static func load() -> WidgetHeadphoneData {
        guard let store = UserDefaults(suiteName: appGroupSuite),
              let data = store.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return WidgetHeadphoneData(
                deviceName: "--",
                connectionStatus: "未连接",
                batteryLeft: "--",
                batteryRight: "--",
                batteryCase: "--",
                ancMode: "关闭"
            )
        }
        return decoded
    }
}
