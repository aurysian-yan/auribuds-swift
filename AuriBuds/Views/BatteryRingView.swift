import SwiftUI

struct BatteryRingView: View {
    let value: Int?

    private var progress: Double {
        guard let value else { return 0 }
        return min(max(Double(value) / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: 4)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy(duration: 0.28), value: progress)

            Text(valueText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(value == nil ? .opacity : .numericText())
                .animation(.snappy(duration: 0.28), value: value)
        }
        .frame(width: 34, height: 34)
    }

    private var valueText: String {
        guard let value else { return "–" }
        return "\(value)"
    }
}

#Preview {
    BatteryRingView(value: 86)
        .padding()
}
