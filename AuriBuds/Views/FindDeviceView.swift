import SwiftUI

struct FindDeviceView: View {
    @ObservedObject var viewModel: EarbudsViewModel
    @ObservedObject private var monitor = BluetoothMonitor.shared
    @State private var pulse = false

    private var discoveredDevices: [BluetoothDeviceSnapshot] {
        monitor.availableDevices.filter { snapshot in
            HeadphoneAdapterRegistry.shared.canControl(snapshot)
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.15))
                                .frame(width: 64, height: 64)

                            if monitor.isScanning {
                                Circle()
                                    .stroke(.blue, lineWidth: 2)
                                    .frame(width: 64, height: 64)
                                    .scaleEffect(pulse ? 1.4 : 1.0)
                                    .opacity(pulse ? 0 : 0.4)
                                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)

                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .symbolEffect(.variableColor.iterative, options: .repeating)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(monitor.isScanning ? "正在扫描附近的设备…" : "扫描已停止")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !monitor.isScanning {
                            Button {
                                monitor.rescan()
                            } label: {
                                Label("重新扫描", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
                .onAppear { pulse = true }
                .onDisappear { pulse = false }
            }
            .listRowBackground(Color.clear)

            if discoveredDevices.isEmpty && !monitor.isScanning {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "wave.3.right")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)

                            Text("未发现设备")
                                .font(.headline)

                            Text("请确保耳机处于配对模式，并在附近范围内")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }

            if !discoveredDevices.isEmpty {
                Section {
                    ForEach(discoveredDevices, id: \.id) { device in
                        FindDeviceRow(
                            device: device,
                            isConnected: device.isConnected,
                            onConnect: {
                                Task {
                                    await viewModel.connect(device: PairedDevice(snapshot: device))
                                }
                            }
                        )
                    }
                } header: {
                    Text("发现的设备")
                }
            }
        }
        .navigationTitle("查找设备")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    monitor.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(monitor.isScanning)
            }
        }
    }
}

private struct FindDeviceRow: View {
    let device: BluetoothDeviceSnapshot
    let isConnected: Bool
    let onConnect: () -> Void

    private var imageName: String? {
        DeviceImageProvider.shared.selectedImageName(for: device)
    }

    var body: some View {
        HStack(spacing: 12) {
            DeviceImageView(
                imageName: imageName,
                fallbackSystemName: device.fallbackSystemName,
                size: CGSize(width: 38, height: 38)
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 15))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? .green : .secondary)
                        .frame(width: 6, height: 6)

                    Text(isConnected ? "已连接" : "未连接")
                        .font(.caption)
                        .foregroundStyle(isConnected ? .green : .secondary)
                }
            }

            Spacer()

            Button {
                onConnect()
            } label: {
                Text("连接")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isConnected)
        }
        .padding(.vertical, 4)
    }
}
