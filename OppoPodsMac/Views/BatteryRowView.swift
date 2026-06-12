import SwiftUI

struct BatteryRowView: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(height: 24)
    }
}

#Preview {
    BatteryRowView(title: "Left", value: "100%")
        .padding()
}
