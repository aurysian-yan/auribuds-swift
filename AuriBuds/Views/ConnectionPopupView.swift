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

    private var popupImageName: String? {
        DeviceImageProvider.shared.connectionPopupImageName(for: state.imageName)
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
                    imageName: popupImageName,
                    fallbackSystemName: "headphones",
                    size: CGSize(width: 38, height: 38)
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

private extension DeviceImageProvider {
    func connectionPopupImageName(for selectedImageName: String?) -> String? {
        guard let selectedImageName else {
            return nil
        }

        if let earbudsPairImageName = earbudsPairImageName(matching: selectedImageName) {
            return earbudsPairImageName
        }

        return NSImage(named: selectedImageName) == nil ? nil : selectedImageName
    }

    func earbudsPairImageName(matching selectedImageName: String) -> String? {
        let candidates = earbudsPairCandidates(from: selectedImageName)
        return candidates.first { NSImage(named: $0) != nil }
    }

    func earbudsPairCandidates(from imageName: String) -> [String] {
        var candidates: [String] = []

        func append(_ candidate: String) {
            guard !candidate.isEmpty, !candidates.contains(candidate) else { return }
            candidates.append(candidate)
        }

        append(imageName)

        if imageName.contains("earbuds_pair") || imageName.contains("buds_pair") {
            return candidates
        }

        // Asset names follow the pattern:
        // OPPO Enco Air4 Pro__夜影灰__earbuds_pair_001
        // Keep the same model + color prefix and prefer the earbuds_pair variant.
        let doubleUnderscoreParts = imageName.components(separatedBy: "__")
        if doubleUnderscoreParts.count >= 3 {
            let prefix = doubleUnderscoreParts.dropLast().joined(separator: "__")
            let lastComponent = doubleUnderscoreParts.last ?? ""
            let suffixPattern = #"_\d+$"#
            let suffixRange = lastComponent.range(of: suffixPattern, options: .regularExpression)
            let suffix = suffixRange.map { String(lastComponent[$0]) } ?? ""

            append("\(prefix)__earbuds_pair\(suffix)")
            append("\(prefix)__earbuds_pair_001")
            append("\(prefix)__buds_pair\(suffix)")
            append("\(prefix)__buds_pair_001")
        }

        let replacements = [
            ("earbuds_pair_001", "earbuds_pair_001"),
            ("case_open", "earbuds_pair"),
            ("case_closed", "earbuds_pair"),
            ("open_case", "earbuds_pair"),
            ("closed_case", "earbuds_pair"),
            ("open", "earbuds_pair"),
            ("closed", "earbuds_pair"),
            ("case", "earbuds_pair"),
            ("charging_box", "earbuds_pair"),
            ("box", "earbuds_pair"),
            ("product", "earbuds_pair"),
            ("device", "earbuds_pair"),
            ("primary", "earbuds_pair"),
            ("main", "earbuds_pair"),
            ("render", "earbuds_pair"),
            ("left_bud", "earbuds_pair"),
            ("right_bud", "earbuds_pair"),
            ("left", "earbuds_pair"),
            ("right", "earbuds_pair")
        ]

        for (source, replacement) in replacements where imageName.contains(source) {
            append(imageName.replacingOccurrences(of: source, with: replacement))
        }

        append("\(imageName)_earbuds_pair")

        let separators: [Character] = ["_", "-"]
        for separator in separators {
            let parts = imageName.split(separator: separator)
            guard parts.count > 1 else { continue }

            let base = parts.dropLast().joined(separator: String(separator))
            append("\(base)\(separator)earbuds_pair")
        }

        return candidates
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
