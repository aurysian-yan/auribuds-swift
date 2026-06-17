import Foundation

struct WidgetHeadphoneData: Codable {
    let deviceName: String
    let connectionStatus: String
    let batteryLeft: String
    let batteryRight: String
    let batteryCase: String
    let ancMode: String
    let isCaseCharging: Bool
    let imageName: String?
    let fallbackSystemName: String

    static let appGroupSuite = "group.top.aurysian.auribuds"
    private static let storageKey = "widgetHeadphoneData"

    func save() {
        guard let data = try? JSONEncoder().encode(self),
              let store = UserDefaults(suiteName: Self.appGroupSuite) else { return }
        store.set(data, forKey: Self.storageKey)
    }
}
