import AppKit
import SwiftUI

enum ConnectionPopupStatus {
    case connected
    case disconnected

    var title: String {
        switch self {
        case .connected:
            return "已连接"
        case .disconnected:
            return "已断开"
        }
    }
}

@MainActor
final class ConnectionPopupState: ObservableObject {
    @Published var deviceName = ""
    @Published var status: ConnectionPopupStatus = .connected
    @Published var batteryLevel: Int?
    @Published var imageName: String?
    @Published var isPresented = false
    @Published var isHiding = false
}

struct ConnectionPopupView: View {
    @ObservedObject var state: ConnectionPopupState

    private var contentScale: CGFloat {
        if state.isPresented {
            return 1
        }

        return state.isHiding ? 0.98 : 0.96
    }

    private var contentOffset: CGFloat {
        if state.isPresented {
            return 0
        }

        return state.isHiding ? -6 : -8
    }

    var body: some View {
        ZStack {
            VStack(alignment: .center, spacing: 2) {
                Text(state.deviceName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                Text(state.status.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 84)

            HStack {
                DeviceImageView(
                    imageName: state.imageName,
                    fallbackSystemName: "headphones",
                    size: CGSize(width: 48, height: 48)
                )
                .frame(width: 46, height: 46)

                Spacer()
                
                HStack() {}
                .frame(width: 46, height: 46)
//                BatteryRingView(value: state.batteryLevel)
            }
            .padding(.horizontal, 14)
        }
        .opacity(state.isPresented ? 1 : 0)
        .scaleEffect(contentScale)
        .offset(y: contentOffset)
        .animation(.snappy(duration: 0.24), value: state.isPresented)
        .animation(.snappy(duration: 0.2), value: state.isHiding)
        .frame(width: 320, height: 60)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(.white.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
    }
}

#Preview {
    let state = ConnectionPopupState()
    state.deviceName = "OPPO Enco Air4 Pro"
    state.batteryLevel = 86
    state.imageName = DeviceImageProvider.shared.primaryImageName(modelName: state.deviceName)
    state.isPresented = true

    return ConnectionPopupView(state: state)
        .padding()
}
