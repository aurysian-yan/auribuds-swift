import SwiftUI

struct ANCControlView: View {
    let selectedMode: ANCMode
    let isEnabled: Bool
    let setMode: (ANCMode) -> Void

    var body: some View {
        HStack {
            Button("Off") {
                setMode(.off)
            }
            .disabled(!isEnabled)

            Button("Transparency") {
                setMode(.transparency)
            }
            .disabled(!isEnabled)
        }
    }
}

#Preview {
    ANCControlView(selectedMode: .off, isEnabled: true) { _ in }
        .padding()
}
