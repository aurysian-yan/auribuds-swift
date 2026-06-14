import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class ConnectionPopupWindowController {
    static let shared = ConnectionPopupWindowController()

    private let size = NSSize(width: 320, height: 60)
    private let state = ConnectionPopupState()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ConnectionPopupView>?
    private var hideWorkItem: DispatchWorkItem?
    private var animationGeneration = 0

    private init() {}

    nonisolated func showConnected(deviceName: String, batteryLevel: Int?, imageName: String? = nil) {
        showConnectedIfNeeded(deviceName: deviceName, batteryLevel: batteryLevel, imageName: imageName)
    }

    nonisolated func showConnectedIfNeeded(deviceName: String, batteryLevel: Int?, imageName: String? = nil) {
        debugLog("showConnectedIfNeeded requested device=\(deviceName), battery=\(batteryLevel.map(String.init) ?? "nil"), mainThread=\(Thread.isMainThread)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.showConnectedOnMain(deviceName: deviceName, batteryLevel: batteryLevel, imageName: imageName)
        }
    }

    nonisolated func updateBatteryLevel(_ batteryLevel: Int?) {
        debugLog("updateBatteryLevel requested battery=\(batteryLevel.map(String.init) ?? "nil"), mainThread=\(Thread.isMainThread)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state.batteryLevel = batteryLevel
            self.debugLogOnMain("updateBatteryLevel applied battery=\(batteryLevel.map(String.init) ?? "nil")")
        }
    }

    nonisolated func hide() {
        debugLog("hide requested mainThread=\(Thread.isMainThread)")

        Task { @MainActor [weak self] in
            self?.hideOnMain()
        }
    }

    private func showConnectedOnMain(deviceName: String, batteryLevel: Int?, imageName: String?) {
        debugLogOnMain("showConnectedIfNeeded entered mainThread=\(Thread.isMainThread)")

        if hideWorkItem != nil {
            debugLogOnMain("cancel old hideWorkItem")
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil

        animationGeneration += 1
        let generation = animationGeneration

        let panel = panel ?? makePanel()
        if self.panel == nil {
            debugLogOnMain("panel created")
        } else {
            debugLogOnMain("panel reused isVisible=\(panel.isVisible), alpha=\(panel.alphaValue)")
        }
        self.panel = panel

        if hostingView == nil {
            let hostingView = NSHostingView(rootView: ConnectionPopupView(state: state))
            hostingView.frame = NSRect(origin: .zero, size: size)
            hostingView.autoresizingMask = [.width, .height]
            self.hostingView = hostingView
            panel.contentView = hostingView
            debugLogOnMain("hostingView created frame=\(hostingView.frame)")
        } else if panel.contentView == nil {
            panel.contentView = hostingView
            debugLogOnMain("hostingView restored to panel")
        }

        state.deviceName = deviceName
        state.status = .connected
        state.batteryLevel = batteryLevel
        state.imageName = imageName ?? DeviceImageProvider.shared.primaryImageName(modelName: deviceName)
        state.isHiding = false

        let screen = screenForPopup()
        let panelFrame = frame(on: screen)
        debugLogOnMain("screen frame=\(screen.frame), visibleFrame=\(screen.visibleFrame)")
        debugLogOnMain("panel target frame=\(panelFrame)")

        panel.setContentSize(size)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(panelFrame, display: true)

        let shouldAnimateIn = !panel.isVisible || !state.isPresented
        if shouldAnimateIn {
            state.isPresented = false
            panel.alphaValue = 0
            debugLogOnMain("prepare show animation isPresented=false, alpha=0")
        } else {
            state.isPresented = true
            panel.alphaValue = 1
            debugLogOnMain("panel already visible, keep isPresented=true, alpha=1")
        }

        panel.displayIfNeeded()
        debugLogOnMain("displayIfNeeded executed contentFrame=\(panel.contentView?.frame.debugDescription ?? "nil")")

        panel.orderFrontRegardless()
        debugLogOnMain("orderFrontRegardless executed isVisible=\(panel.isVisible)")
        panel.order(.above, relativeTo: 0)
        debugLogOnMain("order above executed isVisible=\(panel.isVisible), frame=\(panel.frame), level=\(panel.level.rawValue)")

        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, generation == self.animationGeneration else {
                Self.debugLog("show animation skipped by generation change")
                return
            }

            withAnimation(.snappy(duration: 0.24)) {
                self.state.isPresented = true
            }
            self.debugLogOnMain("state.isPresented set true")

            if let panel {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                } completionHandler: {
                    Self.debugLog("show alpha animation completed alpha=\(panel.alphaValue), isVisible=\(panel.isVisible)")
                }
            }

            self.scheduleAutoHide(duration: 3)
        }
    }

    private func hideOnMain() {
        debugLogOnMain("hide entered mainThread=\(Thread.isMainThread)")

        if hideWorkItem != nil {
            debugLogOnMain("cancel hideWorkItem in hide")
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let panel, panel.isVisible || state.isPresented else {
            state.isPresented = false
            state.isHiding = false
            state.imageName = nil
            debugLogOnMain("hide skipped no visible panel")
            return
        }

        animationGeneration += 1
        let generation = animationGeneration
        state.isHiding = true

        withAnimation(.snappy(duration: 0.2)) {
            state.isPresented = false
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, generation == self.animationGeneration else { return }
                panel?.orderOut(nil)
                self.state.isHiding = false
                self.state.imageName = nil
                self.debugLogOnMain("hide completed orderOut isVisible=\(panel?.isVisible ?? false)")
            }
        }
    }

    private func scheduleAutoHide(duration: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        debugLogOnMain("hideWorkItem rebuilt duration=\(duration)")
    }

    private func makePanel() -> NSPanel {
        let panel = ConnectionPopupPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 16
        )
        return NSRect(origin: origin, size: size)
    }

    private func screenForPopup() -> NSScreen {
        NSScreen.main ?? NSScreen.screens[0]
    }

    private nonisolated static func debugLog(_ message: String) {
        #if DEBUG
        print("[ConnectionPopup] \(message)")
        #endif
    }

    private nonisolated func debugLog(_ message: String) {
        Self.debugLog(message)
    }

    private func debugLogOnMain(_ message: String) {
        Self.debugLog(message)
    }
}

final class ConnectionPopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
