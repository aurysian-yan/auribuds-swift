import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var viewModel: EarbudsViewModel
#if DEBUG
    @ObservedObject var testDeviceStore: DebugTestDeviceStore
#endif

    private var devices: [PairedDevice] {
#if DEBUG
        return viewModel.availableDisplayDevices(testDevices: testDeviceStore.devices)
#else
        return viewModel.pairedDevices
#endif
    }

    var body: some View {
        Form {
            Section("设备") {
                ForEach(devices) { device in
                    DeviceSettingsRow(device: device)
                }
            }
#if DEBUG
            Section("样例设备") {
                DebugTestDeviceManagerView(store: testDeviceStore)
            }
#endif
            Section("外观") {
                LabeledContent("主题", value: "跟随系统")
            }
            Section("关于") {
                AboutAuriBudsView()
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, -8)
    }
}

#if DEBUG
private struct DebugTestDeviceManagerView: View {
    @ObservedObject var store: DebugTestDeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.availableOptions.isEmpty {
                Text("暂无可添加设备")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("支持设备", selection: $store.selectedOptionId) {
                    ForEach(store.availableOptions) { option in
                        Text(option.pickerTitle)
                            .tag(option.id)
                    }
                }

                Button("添加") {
                    store.addSelectedDevice()
                }
                .disabled(store.selectedOptionId.isEmpty)
            }

            if !store.devices.isEmpty {
                Divider()

                ForEach(store.devices) { device in
                    HStack(spacing: 12) {
                        DeviceImageView(
                            imageName: device.imageName,
                            fallbackSystemName: device.fallbackSystemName,
                            size: CGSize(width: 36, height: 36)
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.displayName)
                                .font(.headline)

                            Text(device.option.colorTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("移除") {
                            store.remove(device)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
#endif

private struct DeviceSettingsRow: View {
    let device: PairedDevice
    @State private var selectedImageName: String

    init(device: PairedDevice) {
        self.device = device
        _selectedImageName = State(initialValue: device.selectedImageName ?? device.defaultImageName ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DeviceImageView(
                    imageName: selectedImageName.isEmpty ? device.defaultImageName : selectedImageName,
                    fallbackSystemName: device.fallbackSystemName,
                    size: CGSize(width: 44, height: 44)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName)
                        .font(.headline)

                    Text(device.lastConnectedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("蓝牙地址", value: device.modelIdentifier)

            if device.availableImageNames.count > 1 {
                Picker("机身颜色", selection: $selectedImageName) {
                    ForEach(device.availableImageNames, id: \.self) { imageName in
                        Text(DeviceImageProvider.shared.displayTitle(for: imageName))
                            .tag(imageName)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedImageName) { _, imageName in
                    DeviceImageProvider.shared.setSelectedImageName(imageName, for: device.id)
                }
            } else if let imageName = device.defaultImageName {
                LabeledContent("机身颜色", value: DeviceImageProvider.shared.displayTitle(for: imageName))
            }
        }
        .padding(.vertical, 6)
    }
}

struct AboutAuriBudsView: View {
    private let appName = Bundle.main.displayName
    private let versionText = Bundle.main.versionDisplayText
    var body: some View {
        VStack(spacing: 18) {
            AppIconView(size: 96)
            VStack(spacing: 6) {
                Text(appName)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                Text(versionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Divider()
                .padding(.vertical, 2)
            VStack(spacing: 6) {
                Text("Multi-brand earbuds control for macOS")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("© 2026 Aurysian Yan")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
    }
}

private struct AppIconView: View {
    let size: CGFloat
    var body: some View {
        if let image = Bundle.main.bestAppIconImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "earbuds")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

private extension Bundle {
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "AuriBuds"
    }
    var versionDisplayText: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1"
        return "Version \(version) (\(build))"
    }
    var bestAppIconImage: NSImage? {
        if let runtimeIcon = NSApp.applicationIconImage {
            return runtimeIcon
        }
        if let iconName = object(forInfoDictionaryKey: "CFBundleIconName") as? String,
           let iconImage = NSImage(named: iconName) {
            return iconImage
        }
        if let iconFile = object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let name = iconFile.replacingOccurrences(of: ".icns", with: "")
            if let iconImage = NSImage(named: name) {
                return iconImage
            }
        }
        return nil
    }
}

#Preview {
    AboutAuriBudsView()
}
