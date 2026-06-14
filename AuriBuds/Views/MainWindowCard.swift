import SwiftUI

struct MainWindowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
    }
}
