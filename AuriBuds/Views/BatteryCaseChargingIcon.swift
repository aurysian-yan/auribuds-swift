import SwiftUI

struct BatteryCaseChargingIcon: View {
    let isCharging: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image("oppobuds.case.fill")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .accessibilityLabel("Case")

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("充电中")
                    .padding(.trailing, -4)
            }
        }
    }
}
