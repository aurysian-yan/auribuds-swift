import AppKit
import SwiftUI

struct DeviceImageView: View {
    let imageName: String?
    let fallbackSystemName: String
    let size: CGSize?

    init(
        imageName: String?,
        fallbackSystemName: String,
        size: CGSize? = nil
    ) {
        self.imageName = imageName
        self.fallbackSystemName = fallbackSystemName
        self.size = size
    }

    var body: some View {
        content
            .modifier(DeviceImageFrameModifier(size: size))
    }

    @ViewBuilder
    private var content: some View {
        if let imageName, let nsImage = NSImage(named: imageName) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            fallbackImage
        }
    }

    private var fallbackImage: some View {
        GeometryReader { geometry in
            Image(systemName: fallbackSystemName)
                .font(.system(
                    size: min(geometry.size.width, geometry.size.height) * 0.46,
                    weight: .regular
                ))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DeviceImageFrameModifier: ViewModifier {
    let size: CGSize?

    func body(content: Content) -> some View {
        if let size {
            content
                .frame(width: size.width, height: size.height)
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
