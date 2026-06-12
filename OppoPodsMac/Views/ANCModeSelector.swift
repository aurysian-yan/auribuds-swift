import SwiftUI

enum ANCModeSelectorSize {
    case compact
    case regular

    var iconSize: CGFloat {
        switch self {
        case .compact:
            return 22
        case .regular:
            return 26
        }
    }

    var controlHeight: CGFloat {
        switch self {
        case .compact:
            return 52
        case .regular:
            return 60
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
                        modeButton(.off, systemImage: "person.crop.circle")
                        modeButton(.transparency, systemImage: "person.crop.circle.dashed")
                        modeButton(.noiseCancellation, systemImage: "person.crop.circle.badge.minus")
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
    }

    private func modeButton(_ mode: ANCMode, systemImage: String) -> some View {
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

                Image(systemName: systemImage)
                    .font(.system(size: size.iconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .scaleEffect(isSelected && !reduceMotion ? 1.04 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isControlDisabled)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: viewModel.ancMode)
    }

    private func modeTitle(_ mode: ANCMode) -> some View {
        let isSelected = viewModel.ancMode == mode

        return Text(mode.localizedTitle)
            .font(size.labelFont)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
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
