#if DEBUG
import Foundation
import SwiftUI

@MainActor
final class DebugTestDeviceStore: ObservableObject {
    static let shared = DebugTestDeviceStore()

    @Published private(set) var devices: [DebugTestDevice]
    @Published var selectedOptionId = ""

    let supportedOptions: [SupportedDeviceOption]
    private let selectedOptionIdsKey = "debugTestDeviceOptionIds"

    var availableOptions: [SupportedDeviceOption] {
        let selectedIds = Set(devices.map(\.option.id))
        return supportedOptions.filter { !selectedIds.contains($0.id) }
    }

    private init() {
        let options = DeviceImageProvider.shared.supportedDeviceOptions()
        let savedIds = UserDefaults.standard.stringArray(forKey: selectedOptionIdsKey) ?? []
        let selectedDevices = savedIds.compactMap { savedId in
            options.first { $0.id == savedId }.map(DebugTestDevice.init(option:))
        }

        supportedOptions = options
        devices = selectedDevices
        let selectedIds = Set(selectedDevices.map(\.option.id))
        selectedOptionId = options.first { !selectedIds.contains($0.id) }?.id ?? ""
    }

    func device(for id: String) -> DebugTestDevice? {
        devices.first { $0.id == id }
    }

    func addSelectedDevice() {
        guard let option = availableOptions.first(where: { $0.id == selectedOptionId }) else { return }
        devices.append(DebugTestDevice(option: option))
        save()
        selectedOptionId = availableOptions.first?.id ?? ""
    }

    func remove(_ device: DebugTestDevice) {
        devices.removeAll { $0.id == device.id }
        save()
        if selectedOptionId.isEmpty {
            selectedOptionId = availableOptions.first?.id ?? ""
        }
    }

    private func save() {
        UserDefaults.standard.set(devices.map(\.option.id), forKey: selectedOptionIdsKey)
    }
}

struct DebugTestDevice: Identifiable, Equatable {
    let option: SupportedDeviceOption

    var id: String {
        "test-device-\(option.id)"
    }

    var displayName: String {
        option.displayName
    }

    var modelIdentifier: String {
        let seed = hexSeed.prefix(6)
        let parts = stride(from: 0, to: seed.count, by: 2).map { offset in
            let start = seed.index(seed.startIndex, offsetBy: offset)
            let end = seed.index(start, offsetBy: min(2, seed.distance(from: start, to: seed.endIndex)))
            return String(seed[start..<end]).uppercased()
        }

        return (["02", "00", "00"] + parts).joined(separator: ":")
    }

    var fallbackSystemName: String {
        "headphones"
    }

    var connectionStatus: ConnectionStatus {
        .connected
    }

    var leftBattery: Int? {
        60 + (seedValue % 41)
    }

    var rightBattery: Int? {
        55 + ((seedValue / 3) % 46)
    }

    var caseBattery: Int? {
        50 + ((seedValue / 7) % 51)
    }

    var isCaseCharging: Bool {
        seedValue.isMultiple(of: 2)
    }

    var ancModeTitle: String {
        ["关闭", "通透模式", "降噪"][seedValue % 3]
    }

    var imageName: String? {
        selectedImageName ?? option.imageName
    }

    var availableImageNames: [String] {
        DeviceImageProvider.shared.availableImageNames(
            productId: option.productId,
            modelName: option.displayName
        )
    }

    var selectedImageName: String? {
        DeviceImageProvider.shared.selectedImageName(
            for: id,
            allowedImageNames: availableImageNames
        )
    }

    var pairedDevice: PairedDevice {
        PairedDevice(
            id: id,
            displayName: displayName,
            modelIdentifier: modelIdentifier,
            lastConnectedAt: nil,
            selectedImageName: selectedImageName ?? option.imageName,
            availableImageNames: availableImageNames,
            snapshot: nil,
            isSystemConnected: true,
            isAppControllable: false,
            fallbackSystemName: fallbackSystemName,
            connectionStatusOverride: connectionStatus
        )
    }

    var displayState: DeviceDisplayState {
        DeviceDisplayState(
            deviceName: displayName,
            connectionStatus: connectionStatus,
            leftBatteryText: batteryText(leftBattery),
            rightBatteryText: batteryText(rightBattery),
            caseBatteryText: batteryText(caseBattery),
            isCaseCharging: isCaseCharging,
            imageName: imageName,
            fallbackSystemName: fallbackSystemName,
            ancModeTitle: ancModeTitle
        )
    }

    private var seedValue: Int {
        option.id.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult &+ Int(scalar.value)
        }
    }

    private var hexSeed: String {
        String(abs(seedValue), radix: 16)
    }

    private func batteryText(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)%"
    }
}

extension EarbudsViewModel {
    func availableDisplayDevices(testDevices: [DebugTestDevice]) -> [PairedDevice] {
        return pairedDevices + testDevices.map(\.pairedDevice)
    }
}
#endif
