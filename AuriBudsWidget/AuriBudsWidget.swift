import AppIntents
import SwiftUI
import WidgetKit

struct OpenAuriBudsIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 AuriBuds"
    static var description: IntentDescription = "打开 AuriBuds 主程序切换降噪模式"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> HeadphoneEntry {
        HeadphoneEntry(date: Date(), data: WidgetHeadphoneData.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadphoneEntry) -> Void) {
        let entry = HeadphoneEntry(date: Date(), data: WidgetHeadphoneData.load())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadphoneEntry>) -> Void) {
        let data = WidgetHeadphoneData.load()
        let entry = HeadphoneEntry(date: Date(), data: data)
        let timeline = Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(120)))
        completion(timeline)
    }
}

struct HeadphoneEntry: TimelineEntry {
    let date: Date
    let data: WidgetHeadphoneData
}

struct AuriBudsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    private var isConnected: Bool {
        entry.data.connectionStatus == "已连接"
    }

    private var isConnecting: Bool {
        ["连接中", "握手中", "重连中"].contains(entry.data.connectionStatus)
    }

    private var statusDotColor: Color {
        if isConnected { return .green }
        if isConnecting { return .accentColor }
        return .secondary
    }

    private var statusDotOpacity: Double {
        isConnecting ? 0.5 : 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusLine

            Text(entry.data.deviceName)
                .font(family == .systemSmall ? .caption.weight(.semibold) : .title3.weight(.medium))
                .fontWidth(.condensed)
                .lineLimit(2)
                .contentTransition(.interpolate)

            batteryRow

            if family == .systemLarge {
                ancButtons
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(family == .systemSmall ? 10 : 16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: family == .systemSmall ? 5 : 7, height: family == .systemSmall ? 5 : 7)
                .opacity(statusDotOpacity)

            Text(entry.data.connectionStatus)
                .font(family == .systemSmall ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
        }
    }

    private var batteryRow: some View {
        HStack(spacing: family == .systemSmall ? 8 : 14) {
            batteryLabel(side: "L", value: entry.data.batteryLeft)
            batteryLabel(side: "R", value: entry.data.batteryRight)
            batteryLabel(side: "仓", value: entry.data.batteryCase)
        }
    }

    private func batteryLabel(side: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(side)
                .font(.system(size: family == .systemSmall ? 9 : 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: family == .systemSmall ? 12 : 14, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var ancButtons: some View {
        let modes: [(String, String)] = [
            ("关闭", "oppobuds.anc.fill"),
            ("通透模式", "oppobuds.transparency.fill"),
            ("降噪", "oppobuds.anc.on.fill")
        ]

        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(modes, id: \.0) { title, imageName in
                    Button(intent: OpenAuriBudsIntent()) {
                        VStack(spacing: 2) {
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .padding(6)
                                .background(
                                    entry.data.ancMode == title
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear
                                )
                                .clipShape(Capsule())
                            Text(title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AuriBudsWidget: Widget {
    let kind: String = "top.aurysian.auribuds.AuriBudsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AuriBudsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AuriBuds")
        .description("查看耳机连接状态和电量")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
