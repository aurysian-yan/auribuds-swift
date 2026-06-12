import SwiftUI

struct DebugLogView: View {
    let events: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if events.isEmpty {
                Text("No events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    Text(event)
                        .font(.caption2)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

#Preview {
    DebugLogView(events: [
        "connect attempt",
        "safe handshake passed",
        "recv frame AA 0F 00 00 06 81 F0"
    ])
    .padding()
}
