import AppKit
import SwiftUI

extension View {
    func mainWindowBehavior(title: String) -> some View {
        background(MainWindowConfigurator(title: title))
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView, coordinator: context.coordinator)
        }
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }

        // 保持 Dock 使用包内 Icon Composer 应用图标。
        // 如果 AppKit/SwiftUI 生命周期代码临时设置了 NSImage，
        // 重置为 nil 可恢复包内原始图标。
        NSApp.applicationIconImage = nil

        window.delegate = coordinator
        window.title = title
        window.titleVisibility = title.isEmpty ? .hidden : .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .automatic
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.fullScreen)
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.minSize = coordinator.minimumSize
        window.maxSize = coordinator.maximumSize
        window.contentMinSize = coordinator.minimumSize
        window.contentMaxSize = coordinator.maximumSize
        coordinator.clampWindowFrame(window)
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        window.isOpaque = false
        window.backgroundColor = .clear
        window.toolbar?.showsBaselineSeparator = false
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        let minimumSize = NSSize(width: 512, height: 720)
        let maximumSize = NSSize(width: 768, height: 1440)

        func windowShouldZoom(_ sender: NSWindow, toFrame newFrame: NSRect) -> Bool {
            false
        }

        func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
            window.frame
        }

        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            clampedSize(frameSize)
        }

        func windowDidResize(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            clampWindowFrame(window)
        }

        func clampWindowFrame(_ window: NSWindow) {
            let currentFrame = window.frame
            let targetSize = clampedSize(currentFrame.size)

            guard currentFrame.size != targetSize else { return }

            var targetFrame = currentFrame
            let topEdge = targetFrame.maxY
            targetFrame.size = targetSize
            targetFrame.origin.y = topEdge - targetSize.height
            window.setFrame(targetFrame, display: true)
        }

        private func clampedSize(_ size: NSSize) -> NSSize {
            NSSize(
                width: min(max(size.width, minimumSize.width), maximumSize.width),
                height: min(max(size.height, minimumSize.height), maximumSize.height)
            )
        }
    }
}
