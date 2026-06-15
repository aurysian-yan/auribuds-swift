import SwiftUI

struct MainWindowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
    }
}

#Preview {
    MainWindowCard {
        VStack(alignment: .leading, spacing: 8) {
            Text("设备")
                .font(.headline)

            Text("OPPO Enco Air4 Pro")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    .frame(width: 320)
}
