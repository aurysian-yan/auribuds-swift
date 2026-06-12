import SwiftUI

struct ANCModeSelector: View {
    @ObservedObject var viewModel: EarbudsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    private var isControlDisabled: Bool {
        viewModel.isBusy || viewModel.isWritingANC
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("降噪模式")
                .font(.callout.weight(.semibold))

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
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, -4)

                HStack(spacing: 0) {
                    ForEach(ANCMode.mainModes, id: \.self) { mode in
                        modeTitle(mode)
                    }
                }
                .opacity(isControlDisabled ? 0.55 : 1)
            }
        }
        .disabled(isControlDisabled)
    }

    private func modeButton(_ mode: ANCMode, systemImage: String) -> some View {
        let isSelected = viewModel.ancMode == mode
        let isUnavailable = mode == .noiseCancellation

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
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .opacity(isUnavailable ? 0.4 : 1)
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
        let isUnavailable = mode == .noiseCancellation

        return Text(mode.localizedTitle)
            .font(.caption)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .opacity(isUnavailable ? 0.45 : 1)
            .frame(maxWidth: .infinity)
    }

    private func handleSelection(_ mode: ANCMode) {
        switch mode {
        case .off:
            Task {
                await viewModel.setANC(.off)
            }
        case .transparency:
            Task {
                await viewModel.setANC(.transparency)
            }
        case .noiseCancellation:
            viewModel.addDebugLog("Noise Cancellation not verified yet")
        }
    }
}

#Preview {
    ANCModeSelector(viewModel: EarbudsViewModel())
        .padding()
        .frame(width: 320)
}
