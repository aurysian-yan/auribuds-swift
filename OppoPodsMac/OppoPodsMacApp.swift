import SwiftUI

@main
struct OppoPodsMacApp: App {
    @StateObject private var viewModel = EarbudsViewModel()

    var body: some Scene {
        WindowGroup("OppoPodsMac", id: "main") {
            MainWindowView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.start()
                }
        }
        .defaultSize(width: 720, height: 520)

        MenuBarExtra("OppoPodsMac", systemImage: "earbuds") {
            MenuBarContentView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
