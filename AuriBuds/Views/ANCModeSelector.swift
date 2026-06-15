import SwiftUI

enum ANCModeSelectorSize {
    case compact
    case regular

    var iconSize: CGFloat {
        switch self {
        case .compact:
            return 26
        case .regular:
            return 32
        }
    }

    var iconFrameSize: CGFloat {
        switch self {
        case .compact:
            return 28
        case .regular:
            return 32
        }
    }

    var controlHeight: CGFloat {
        switch self {
        case .compact:
            return 48
        case .regular:
            return 52
        }
    }

    var titleFont: Font {
        switch self {
        case .compact:
            return .callout.weight(.semibold)
        case .regular:
            return .headline
        }
    }

    var labelFont: Font {
        switch self {
        case .compact:
            return .caption
        case .regular:
            return .callout
        }
    }
}

struct ANCModeSelector: View {
    @ObservedObject var viewModel: EarbudsViewModel
    var size: ANCModeSelectorSize = .compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @State private var symbolBounceTrigger = 0
    @State private var detailLevels: [ANCMode: Double] = [
        .noiseCancellation: 1,
        .transparency: 1
    ]

    private var isControlDisabled: Bool {
        viewModel.isBusy || viewModel.isWritingANC
    }

    private var detailOption: ANCDetailOption? {
        ANCDetailOption.option(for: viewModel.ancMode, deviceName: viewModel.state.deviceName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("降噪模式")
                .font(size.titleFont)

            VStack(spacing: 4) {
                ZStack {
                    Capsule()
                        .fill(Color.black.opacity(0.18))

                    HStack(spacing: 0) {
                        modeButton(.off, imageName: "oppobuds.anc.fill")
                        modeButton(.transparency, imageName: "oppobuds.transparency.fill")
                        modeButton(.noiseCancellation, imageName: "oppobuds.anc.on.fill")
                    }
                    .padding(4)
                }
                .frame(height: size.controlHeight)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, -4)

                HStack(spacing: 0) {
                    ForEach(ANCMode.mainModes, id: \.self) { mode in
                        modeTitle(mode)
                    }
                }
            }

            if let detailOption {
                detailSlider(detailOption)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .disabled(isControlDisabled)
        .onChange(of: viewModel.ancMode) { _, _ in
            guard !reduceMotion else { return }
            symbolBounceTrigger += 1
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: detailOption?.id)
    }

    private func modeButton(_ mode: ANCMode, imageName: String) -> some View {
        let isSelected = viewModel.ancMode == mode

        return Button {
            handleSelection(mode)
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(
                            Capsule()
                                .fill(.white.opacity(0.16))
                        )
                        .matchedGeometryEffect(id: "selectedANCModeCapsule", in: selectionNamespace)
                }

                modeIcon(mode, imageName: imageName, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isControlDisabled)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: viewModel.ancMode)
    }

    @ViewBuilder
    private func modeIcon(_ mode: ANCMode, imageName: String, isSelected: Bool) -> some View {
        let icon = Image(imageName)
            .symbolRenderingMode(mode == .off ? .palette : .hierarchical)
            .imageScale(.small)
            .font(.system(size: size.iconSize, weight: .regular))
            .foregroundStyle(
                isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary),
                isSelected ? AnyShapeStyle(.primary.opacity(0.45)) : AnyShapeStyle(.secondary.opacity(0.32))
            )
            .frame(width: size.iconFrameSize, height: size.iconFrameSize, alignment: .center)
            .scaleEffect(isSelected && !reduceMotion ? 1.04 : 1)

        if isSelected && !reduceMotion {
            icon.symbolEffect(.bounce, value: symbolBounceTrigger)
        } else {
            icon
        }
    }

    private func modeTitle(_ mode: ANCMode) -> some View {
        let isSelected = viewModel.ancMode == mode

        return Text(mode.localizedTitle)
            .font(.system(size: 12))
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, -4)
    }

    private func handleSelection(_ mode: ANCMode) {
        Task {
            await viewModel.setANC(mode)
        }
    }

    private func detailSlider(_ option: ANCDetailOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(option.title)
                    .font(.callout.weight(.medium))

                Spacer()

                Text(option.title(for: detailValue(for: option)))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: detailBinding(for: option),
                in: option.range,
                step: 1
            )

            ANCDetailLevelTextStrip(titles: option.levelTitles)
        }
    }

    private func detailBinding(for option: ANCDetailOption) -> Binding<Double> {
        Binding {
            detailValue(for: option)
        } set: { value in
            detailLevels[option.mode] = option.clamped(value)
        }
    }

    private func detailValue(for option: ANCDetailOption) -> Double {
        option.clamped(detailLevels[option.mode] ?? option.defaultValue)
    }
}

private struct ANCDetailOption: Identifiable, Equatable {
    let id: String
    let mode: ANCMode
    let title: String
    let levelTitles: [String]
    let defaultValue: Double

    var range: ClosedRange<Double> {
        0...Double(max(levelTitles.count - 1, 0))
    }

    func title(for value: Double) -> String {
        levelTitles[index(for: value)]
    }

    func clamped(_ value: Double) -> Double {
        min(max(value.rounded(), range.lowerBound), range.upperBound)
    }

    private func index(for value: Double) -> Int {
        min(max(Int(clamped(value)), 0), max(levelTitles.count - 1, 0))
    }

    static func option(for mode: ANCMode, deviceName: String) -> ANCDetailOption? {
        if XiaomiDeviceProfile.isLikelyXiaomiAudioDevice(deviceName) {
            return xiaomiOption(for: mode)
        }

        if OppoDeviceProfile.isLikelyOppoAudioDevice(deviceName) {
            return oppoOption(for: mode)
        }

        return nil
    }

    private static func oppoOption(for mode: ANCMode) -> ANCDetailOption? {
        guard mode == .noiseCancellation else { return nil }

        return ANCDetailOption(
            id: "oppo-noise-cancellation",
            mode: mode,
            title: "降噪强度",
            levelTitles: ["深度降噪", "中度降噪", "轻度降噪", "智能切换"],
            defaultValue: 0
        )
    }

    private static func xiaomiOption(for mode: ANCMode) -> ANCDetailOption? {
        switch mode {
        case .noiseCancellation:
            return ANCDetailOption(
                id: "xiaomi-noise-cancellation",
                mode: mode,
                title: "降噪强度",
                levelTitles: ["深度降噪", "中度降噪", "轻度降噪", "自适应"],
                defaultValue: 1
            )
        case .transparency:
            return ANCDetailOption(
                id: "xiaomi-transparency",
                mode: mode,
                title: "通透强度",
                levelTitles: ["标准", "环境增强", "人声增强"],
                defaultValue: 2
            )
        case .off:
            return nil
        }
    }
}

private struct ANCDetailLevelTextStrip: View {
    let titles: [String]

    var body: some View {
        GeometryReader { geometry in
            let count = max(titles.count, 1)
            let trackInset: CGFloat = 10
            let availableWidth = max(geometry.size.width - trackInset * 2, 0)

            ZStack(alignment: .leading) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: labelWidth(totalWidth: geometry.size.width, count: count))
                        .position(
                            x: xPosition(index: index, count: count, inset: trackInset, width: availableWidth),
                            y: geometry.size.height / 2
                        )
                }
            }
        }
        .frame(height: 16)
    }

    private func xPosition(index: Int, count: Int, inset: CGFloat, width: CGFloat) -> CGFloat {
        guard count > 1 else { return inset + width / 2 }

        return inset + width * CGFloat(index) / CGFloat(count - 1)
    }

    private func labelWidth(totalWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return totalWidth }

        return totalWidth / CGFloat(count)
    }
}

#Preview {
    ANCModeSelector(viewModel: EarbudsViewModel())
        .padding()
        .frame(width: 320)
}
