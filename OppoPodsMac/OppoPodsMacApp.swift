import SwiftUI

@main
struct OppoPodsMacApp: App {
    @StateObject private var viewModel = EarbudsViewModel()

    var body: some Scene {
        MenuBarExtra("OppoPods", systemImage: "earbuds") {
            MenuBarContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
