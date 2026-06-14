import SwiftUI

struct BatteryRowView<Title: View>: View {
    let title: Title
    let value: String

    init(value: String, @ViewBuilder title: () -> Title) {
        self.value = value
        self.title = title()
    }

    var body: some View {
        HStack(spacing: 4) {
            title

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: value)
        }
        .padding(.trailing, 4)
    }
}
