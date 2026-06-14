import Foundation

struct PairedDevice: Identifiable, Equatable {
    let id: String
    let displayName: String
    let modelIdentifier: String
    let lastConnectedAt: Date?
    let selectedImageName: String?
    let availableImageNames: [String]
    let snapshot: BluetoothDeviceSnapshot?
    let isSystemConnected: Bool
    let isAppControllable: Bool
    let fallbackSystemName: String
    let connectionStatusOverride: ConnectionStatus?

    init(
        id: String,
        displayName: String,
        modelIdentifier: String,
        lastConnectedAt: Date?,
        selectedImageName: String?,
        availableImageNames: [String],
        snapshot: BluetoothDeviceSnapshot?,
        isSystemConnected: Bool,
        isAppControllable: Bool,
        fallbackSystemName: String,
        connectionStatusOverride: ConnectionStatus? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.modelIdentifier = modelIdentifier
        self.lastConnectedAt = lastConnectedAt
        self.selectedImageName = selectedImageName
        self.availableImageNames = availableImageNames
        self.snapshot = snapshot
        self.isSystemConnected = isSystemConnected
        self.isAppControllable = isAppControllable
        self.fallbackSystemName = fallbackSystemName
        self.connectionStatusOverride = connectionStatusOverride
    }

    init(state: EarbudsState) {
        let provider = DeviceImageProvider.shared
        let deviceId = provider.selectionKey(for: state)
        let deviceName = state.currentDevice?.name ?? state.deviceName

        self.init(
            id: deviceId,
            displayName: deviceName,
            modelIdentifier: state.currentDevice?.address ?? state.deviceName,
            lastConnectedAt: state.currentDevice?.timestamp,
            selectedImageName: provider.selectedImageName(for: state),
            availableImageNames: provider.availableImageNames(for: state),
            snapshot: state.currentDevice,
            isSystemConnected: state.systemBluetoothConnected,
            isAppControllable: state.currentDevice.map { HeadphoneAdapterRegistry.shared.canControl($0) } ?? true,
            fallbackSystemName: state.currentDevice?.fallbackSystemName ?? "headphones"
        )
    }

    init(snapshot: BluetoothDeviceSnapshot, isAppControllable: Bool? = nil) {
        let provider = DeviceImageProvider.shared

        self.init(
            id: provider.selectionKey(for: snapshot),
            displayName: snapshot.name,
            modelIdentifier: snapshot.address.isEmpty ? snapshot.name : snapshot.address,
            lastConnectedAt: snapshot.timestamp,
            selectedImageName: provider.selectedImageName(for: snapshot),
            availableImageNames: provider.availableImageNames(for: snapshot),
            snapshot: snapshot,
            isSystemConnected: snapshot.isConnected,
            isAppControllable: isAppControllable ?? HeadphoneAdapterRegistry.shared.canControl(snapshot),
            fallbackSystemName: snapshot.fallbackSystemName
        )
    }

    var defaultImageName: String? {
        availableImageNames.first
    }

    var lastConnectedText: String {
        guard let lastConnectedAt else {
            return "最近连接：暂无记录"
        }

        return "最近连接：\(Self.dateFormatter.string(from: lastConnectedAt))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
