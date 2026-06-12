import SwiftUI

struct BatteryRowView<Title: View>: View {
    let title: Title
    let value: String

    init(value: String, @ViewBuilder title: () -> Title) {
        self.value = value
        self.title = title()
    }

    var body: some View {
        HStack {
            title
            Text(value)
        }
    }
}
