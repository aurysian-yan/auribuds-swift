import AppKit
import SwiftUI

struct DebugLogPanelView: View {
    let events: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Debug Log")
                    .font(.headline)

                Spacer()

                Button("复制日志") {
                    copyLogs()
                }
                .disabled(events.isEmpty)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(minWidth: 240, maxWidth: 280, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
        }
    }

    private func truncated(_ event: String) -> String {
        let limit = 180
        guard event.count > limit else {
            return event
        }

        return String(event.prefix(limit)) + "..."
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(events.joined(separator: "\n"), forType: .string)
    }
}

#Preview {
    DebugLogPanelView(events: [
        "auto connect attempt",
        "safe handshake passed",
        "recv frame AA 0F 00 00 06 81 F0 03 00 03 01 64 02 64 03 64"
    ])
    .padding()
}
