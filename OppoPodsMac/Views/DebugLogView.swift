import SwiftUI

struct DebugLogView: View {
    let events: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if events.isEmpty {
                Text("暂无日志")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    Text(truncated(event))
                        .font(.caption2)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func truncated(_ event: String) -> String {
        let limit = 180
        guard event.count > limit else {
            return event
        }

        return String(event.prefix(limit)) + "..."
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
