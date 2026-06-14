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

    private var isControlDisabled: Bool {
        viewModel.isBusy || viewModel.isWritingANC
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
        }
        .disabled(isControlDisabled)
        .onChange(of: viewModel.ancMode) { _, _ in
            guard !reduceMotion else { return }
            symbolBounceTrigger += 1
        }
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
}

#Preview {
    ANCModeSelector(viewModel: EarbudsViewModel())
        .padding()
        .frame(width: 320)
}
