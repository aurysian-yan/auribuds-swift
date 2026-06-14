import AppKit
import SwiftUI

struct LogsPageView: View {
    @ObservedObject var viewModel: EarbudsViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                MainWindowCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前连接状态")
                            .font(.headline)

                        Text(viewModel.state.connectionStatus.localizedTitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("最近错误")
                            .font(.headline)

                        Text(viewModel.state.lastError ?? "暂无错误")
                            .font(.callout)
                            .foregroundStyle(viewModel.state.lastError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MainWindowCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("日志列表")
                                .font(.headline)

                            Spacer()

                            Button("复制日志") {
                                copyLogs()
                            }
                            .disabled(viewModel.debugEvents.isEmpty)

                            Button("清空日志") {}
                                .disabled(true)
                        }

                        if viewModel.debugEvents.isEmpty {
                            Text("暂无日志")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(viewModel.debugEvents.enumerated()), id: \.offset) { _, event in
                                    Text(event)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.debugEvents.joined(separator: "\n"), forType: .string)
    }
}
