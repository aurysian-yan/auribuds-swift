import SwiftUI

struct BatteryCardView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
        }
    }
}

#Preview {
    BatteryCardView(title: "Left", value: "100%")
        .padding()
}
