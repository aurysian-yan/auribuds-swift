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
    let imageSet: DeviceImageSet
}

final class DeviceImageProvider {
    static let shared = DeviceImageProvider()

    private let descriptors: [DeviceImageDescriptor]
    private let selectedImageNameKeyPrefix = "selectedDeviceImageName."
    private let defaultImageSet = DeviceImageSet(
        primary: "oppo_enco_air4_pro_white",
        caseImage: "oppo_enco_air4_pro_black",
        leftBud: nil,
        rightBud: nil
    )

    private init() {
        descriptors = [
            DeviceImageDescriptor(
                productId: "oppo_enco_air4_pro",
                colorId: "white",
                modelName: "OPPO Enco Air4 Pro",
                imageSet: DeviceImageSet(
                    primary: "oppo_enco_air4_pro_white",
                    caseImage: "oppo_enco_air4_pro_white",
                    leftBud: nil,
                    rightBud: nil
                )
            ),
            DeviceImageDescriptor(
                productId: "oppo_enco_air4_pro",
                colorId: "black",
                modelName: "OPPO Enco Air4 Pro",
                imageSet: DeviceImageSet(
                    primary: "oppo_enco_air4_pro_black",
                    caseImage: "oppo_enco_air4_pro_black",
                    leftBud: nil,
                    rightBud: nil
                )
            )
        ]
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
        let normalizedProductId = normalized(productId)
        let normalizedColorId = colorKey(from: colorId) ?? colorKey(from: modelName)

        if let normalizedProductId {
            if let descriptor = descriptors.first(where: { descriptor in
                normalized(descriptor.productId) == normalizedProductId &&
                normalized(descriptor.colorId) == normalizedColorId
            }) {
                return validated(descriptor.imageSet)
            }

            if let descriptor = descriptors.first(where: { descriptor in
                normalized(descriptor.productId) == normalizedProductId
            }) {
                return validated(descriptor.imageSet)
            }
        }

        if let descriptor = descriptors.first(where: { descriptor in
            matches(modelName: modelName, descriptor: descriptor) &&
                (normalizedColorId == nil || normalized(descriptor.colorId) == normalizedColorId)
        }) {
            return validated(descriptor.imageSet)
        }

        if modelName == nil && normalizedProductId == nil {
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
        let normalizedProductId = normalized(productId)
        let matchingDescriptors = descriptors.filter { descriptor in
            if let normalizedProductId {
                return normalized(descriptor.productId) == normalizedProductId
            }

            return matches(modelName: modelName, descriptor: descriptor)
        }

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
            switch descriptor.colorId {
            case "white":
                return "白色"
            case "black":
                return "黑色"
            default:
                return descriptor.colorId ?? imageName
            }
        }

        return imageName
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

    private func matches(modelName: String?, descriptor: DeviceImageDescriptor) -> Bool {
        guard let modelName, let descriptorModelName = descriptor.modelName else {
            return false
        }

        return normalized(modelName)?.contains(normalized(descriptorModelName) ?? "") == true
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

        if value.contains("black") || value.contains("dark") || value.contains("night") || value.contains("星夜") || value.contains("黑") {
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
}
