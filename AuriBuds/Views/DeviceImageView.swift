import AppKit
import SwiftUI

struct DeviceImageView: View {
    let imageName: String?
    let fallbackSystemName: String
    let size: CGSize?
    let maxSize: CGFloat?

    init(
        imageName: String?,
        fallbackSystemName: String,
        size: CGSize? = nil,
        maxSize: CGFloat? = nil
    ) {
        self.imageName = imageName
        self.fallbackSystemName = fallbackSystemName
        self.size = size
        self.maxSize = maxSize
    }

    var body: some View {
        content
            .modifier(DeviceImageFrameModifier(size: size, maxSize: maxSize))
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
    let maxSize: CGFloat?

    func body(content: Content) -> some View {
        if let size {
            content
                .frame(width: size.width, height: size.height)
        } else if let maxSize {
            content
                .frame(maxWidth: maxSize, maxHeight: maxSize)
                .aspectRatio(1, contentMode: .fit)
        } else {
            content
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        DeviceImageView(
            imageName: "oppo_enco_air4_pro_black",
            fallbackSystemName: "headphones",
            size: CGSize(width: 120, height: 120)
        )

        DeviceImageView(
            imageName: nil,
            fallbackSystemName: "headphones",
            size: CGSize(width: 120, height: 120)
        )
    }
    .padding()
}
