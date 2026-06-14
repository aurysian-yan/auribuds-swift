import AppKit
import Foundation

struct DeviceImageSet {
    let primary: String?
    let caseImage: String?
    let leftBud: String?
    let rightBud: String?

    static let empty = DeviceImageSet(primary: nil, caseImage: nil, leftBud: nil, rightBud: nil)
}

struct DeviceImageDescriptor {
    let productId: String?
    let colorId: String?
    let modelName: String?
    let displayTitle: String
    let imageSet: DeviceImageSet
}

struct SupportedDeviceOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let productId: String?
    let colorId: String?
    let colorTitle: String
    let imageName: String?

    var pickerTitle: String {
        "\(displayName) · \(colorTitle)"
    }
}

final class DeviceImageProvider {
    static let shared = DeviceImageProvider()

    private let descriptors: [DeviceImageDescriptor]
    private let selectedImageNameKeyPrefix = "selectedDeviceImageName."
    private var defaultImageSet: DeviceImageSet {
        descriptors.first?.imageSet ?? .empty
    }

    private init() {
        descriptors = DeviceImageDescriptor.generatedCatalog
    }

    func imageSet(for state: EarbudsState) -> DeviceImageSet {
        let imageSet = imageSet(
            productId: nil,
            colorId: nil,
            modelName: state.currentDevice?.name ?? state.deviceName
        )

        guard let selectedImageName = selectedImageName(for: state),
              availableImageName(selectedImageName) != nil else {
            return imageSet
        }

        return DeviceImageSet(
            primary: selectedImageName,
            caseImage: selectedImageName,
            leftBud: imageSet.leftBud,
            rightBud: imageSet.rightBud
        )
    }

    func imageSet(for snapshot: BluetoothDeviceSnapshot?) -> DeviceImageSet {
        let imageSet = imageSet(productId: nil, colorId: nil, modelName: snapshot?.name)

        guard let snapshot,
              let selectedImageName = selectedImageName(for: snapshot),
              availableImageName(selectedImageName) != nil else {
            return imageSet
        }

        return DeviceImageSet(
            primary: selectedImageName,
            caseImage: selectedImageName,
            leftBud: imageSet.leftBud,
            rightBud: imageSet.rightBud
        )
    }

    func imageSet(productId: String? = nil, colorId: String? = nil, modelName: String? = nil) -> DeviceImageSet {
        let normalizedColorId = normalized(colorId) ?? colorKey(from: modelName)
        let matchingDescriptors = matchingDescriptors(productId: productId, modelName: modelName)

        if let descriptor = matchingDescriptors.first(where: { colorMatches(normalizedColorId, descriptor: $0) }) {
            return validated(descriptor.imageSet)
        }

        if let descriptor = matchingDescriptors.first {
            return validated(descriptor.imageSet)
        }

        if modelName == nil && productId == nil {
            return validated(defaultImageSet)
        }

        return .empty
    }

    func primaryImageName(for state: EarbudsState) -> String? {
        imageSet(for: state).primary
    }

    func primaryImageName(for snapshot: BluetoothDeviceSnapshot?) -> String? {
        imageSet(for: snapshot).primary
    }

    func primaryImageName(productId: String? = nil, colorId: String? = nil, modelName: String? = nil) -> String? {
        imageSet(productId: productId, colorId: colorId, modelName: modelName).primary
    }

    func availableImageNames(for state: EarbudsState) -> [String] {
        availableImageNames(
            productId: nil,
            modelName: state.currentDevice?.name ?? state.deviceName
        )
    }

    func availableImageNames(for snapshot: BluetoothDeviceSnapshot) -> [String] {
        availableImageNames(productId: nil, modelName: snapshot.name)
    }

    func availableImageNames(productId: String? = nil, modelName: String? = nil) -> [String] {
        let matchingDescriptors = matchingDescriptors(productId: productId, modelName: modelName)

        let imageNames = matchingDescriptors.compactMap { availableImageName($0.imageSet.primary) }

        if imageNames.isEmpty,
           productId == nil,
           modelName == nil,
           let defaultImageName = availableImageName(defaultImageSet.primary) {
            return [defaultImageName]
        }

        return unique(imageNames)
    }

    func selectedImageName(for state: EarbudsState) -> String? {
        selectedImageName(for: selectionKey(for: state), allowedImageNames: availableImageNames(for: state))
    }

    func selectedImageName(for snapshot: BluetoothDeviceSnapshot) -> String? {
        selectedImageName(for: selectionKey(for: snapshot), allowedImageNames: availableImageNames(for: snapshot))
    }

    func selectedImageName(for deviceId: String, allowedImageNames: [String]) -> String? {
        guard let imageName = UserDefaults.standard.string(forKey: selectedImageNameKey(for: deviceId)),
              allowedImageNames.contains(imageName),
              availableImageName(imageName) != nil else {
            return nil
        }

        return imageName
    }

    func setSelectedImageName(_ imageName: String?, for state: EarbudsState) {
        setSelectedImageName(imageName, for: selectionKey(for: state))
    }

    func setSelectedImageName(_ imageName: String?, for deviceId: String) {
        let key = selectedImageNameKey(for: deviceId)

        guard let imageName else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        UserDefaults.standard.set(imageName, forKey: key)
    }

    func selectionKey(for state: EarbudsState) -> String {
        if let deviceAddress = normalized(state.currentDevice?.address ?? state.deviceAddress) {
            return deviceAddress
        }

        return normalized(state.currentDevice?.name ?? state.deviceName) ?? "default"
    }

    func selectionKey(for snapshot: BluetoothDeviceSnapshot) -> String {
        normalized(snapshot.address) ?? normalized(snapshot.name) ?? "default"
    }

    func displayTitle(for imageName: String) -> String {
        if let descriptor = descriptors.first(where: { $0.imageSet.primary == imageName }) {
            return descriptor.displayTitle
        }

        return imageName
    }

    func supportedDeviceOptions() -> [SupportedDeviceOption] {
        descriptors.compactMap { descriptor in
            let displayName = descriptor.modelName ?? descriptor.productId
            guard let displayName,
                  let imageName = availableImageName(descriptor.imageSet.primary) else {
                return nil
            }

            let optionId = [
                identifier(descriptor.productId),
                identifier(descriptor.colorId),
                identifier(descriptor.imageSet.primary)
            ]
                .compactMap { $0 }
                .joined(separator: "-")

            return SupportedDeviceOption(
                id: optionId,
                displayName: displayName,
                productId: descriptor.productId,
                colorId: descriptor.colorId,
                colorTitle: descriptor.displayTitle,
                imageName: imageName
            )
        }
        .sorted { first, second in
            first.pickerTitle.localizedStandardCompare(second.pickerTitle) == .orderedAscending
        }
    }

    private func validated(_ imageSet: DeviceImageSet) -> DeviceImageSet {
        DeviceImageSet(
            primary: availableImageName(imageSet.primary),
            caseImage: availableImageName(imageSet.caseImage),
            leftBud: availableImageName(imageSet.leftBud),
            rightBud: availableImageName(imageSet.rightBud)
        )
    }

    private func availableImageName(_ imageName: String?) -> String? {
        guard let imageName, NSImage(named: imageName) != nil else {
            return nil
        }

        return imageName
    }

    private func selectedImageNameKey(for deviceId: String) -> String {
        selectedImageNameKeyPrefix + deviceId
    }

    private func unique(_ imageNames: [String]) -> [String] {
        var seen = Set<String>()

        return imageNames.filter { imageName in
            seen.insert(imageName).inserted
        }
    }

    private func matchingDescriptors(productId: String?, modelName: String?) -> [DeviceImageDescriptor] {
        if let productId = identifier(productId) {
            return descriptors.filter { identifier($0.productId) == productId }
        }

        let matchedDescriptors = descriptors.filter { matches(modelName: modelName, descriptor: $0) }
        let maximumModelLength = matchedDescriptors
            .compactMap { identifier($0.modelName)?.count }
            .max()

        guard let maximumModelLength else {
            return []
        }

        return matchedDescriptors.filter { identifier($0.modelName)?.count == maximumModelLength }
    }

    private func colorMatches(_ colorId: String?, descriptor: DeviceImageDescriptor) -> Bool {
        guard let colorId else {
            return true
        }

        return normalized(descriptor.colorId) == colorId || colorKey(from: descriptor.colorId) == colorId
    }

    private func matches(modelName: String?, descriptor: DeviceImageDescriptor) -> Bool {
        guard let modelName = identifier(modelName),
              let descriptorModelName = identifier(descriptor.modelName) else {
            return false
        }

        return modelName.contains(descriptorModelName)
    }

    private func isKnownFamily(_ modelName: String?) -> Bool {
        guard let modelName = normalized(modelName) else {
            return true
        }

        return ["oppo", "oneplus", "realme", "enco", "buds"].contains { modelName.contains($0) }
    }

    private func colorKey(from value: String?) -> String? {
        guard let value = normalized(value) else {
            return nil
        }

        if value.contains("black") ||
            value.contains("dark") ||
            value.contains("gray") ||
            value.contains("grey") ||
            value.contains("night") ||
            value.contains("星夜") ||
            value.contains("暗") ||
            value.contains("灰") ||
            value.contains("黑") ||
            value.contains("夜") {
            return "black"
        }

        if value.contains("white") || value.contains("light") || value.contains("白") {
            return "white"
        }

        return nil
    }

    private func normalized(_ value: String?) -> String? {
        let normalizedValue = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let normalizedValue, !normalizedValue.isEmpty else {
            return nil
        }

        return normalizedValue
    }

    private func identifier(_ value: String?) -> String? {
        guard let normalizedValue = normalized(value) else {
            return nil
        }

        let identifier = normalizedValue.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }

        guard !identifier.isEmpty else {
            return nil
        }

        return String(String.UnicodeScalarView(identifier))
    }
}
