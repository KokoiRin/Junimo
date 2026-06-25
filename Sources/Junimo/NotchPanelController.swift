import AppKit
import CoreGraphics
import JunimoCore
import QuartzCore
import SwiftUI

final class JunimoPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class NotchPanelController {
    private let coordinator: TaskCoordinator
    private let panel: JunimoPanel
    private let collapsedSize = NSSize(width: 420, height: 28)
    private let topWindowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
    private var screenChangeObserver: NSObjectProtocol?

    init(coordinator: TaskCoordinator) {
        self.coordinator = coordinator

        panel = JunimoPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.level = topWindowLevel

        let view = JunimoSurfaceView(coordinator: coordinator)
        panel.contentView = NSHostingView(rootView: view)

        coordinator.expansionDidChange = { [weak self] isExpanded in
            DispatchQueue.main.async {
                self?.resize(isExpanded: isExpanded)
            }
        }

        coordinator.layoutPreferencesDidChange = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resize(isExpanded: self.coordinator.isExpanded)
            }
        }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.pinToTopEdge(isExpanded: self.coordinator.isExpanded)
        }
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    func show() {
        let shouldFadeIn = !panel.isVisible
        resize(isExpanded: coordinator.isExpanded)
        if shouldFadeIn {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        pinToTopEdge(isExpanded: coordinator.isExpanded)
        if shouldFadeIn {
            fadeIn()
        }
    }

    func expandAndShow() {
        let shouldFadeIn = !panel.isVisible
        coordinator.pointerEntered()
        resize(isExpanded: true)
        if shouldFadeIn {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        pinToTopEdge(isExpanded: true)
        if shouldFadeIn {
            fadeIn()
        }
    }

    func diagnostics() -> PanelDiagnostics {
        let frame = panel.frame
        return PanelDiagnostics(
            isVisible: panel.isVisible,
            isFloatingPanel: panel.isFloatingPanel,
            level: Int(panel.level.rawValue),
            frameX: frame.origin.x,
            frameY: frame.origin.y,
            frameWidth: frame.width,
            frameHeight: frame.height,
            screenMaxY: Double(targetScreen()?.frame.maxY ?? frame.maxY)
        )
    }

    private func resize(isExpanded: Bool) {
        let size = isExpanded
            ? NSSize(width: coordinator.preferences.expandedWidth, height: coordinator.preferences.expandedHeight)
            : collapsedSize
        guard let screen = targetScreen() else {
            panel.setFrame(NSRect(origin: .zero, size: size), display: true, animate: false)
            return
        }

        let screenFrame = screen.frame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        panel.level = topWindowLevel
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: false)
    }

    private func pinToTopEdge(isExpanded: Bool) {
        guard let screen = targetScreen() else {
            return
        }
        let size = isExpanded
            ? NSSize(width: coordinator.preferences.expandedWidth, height: coordinator.preferences.expandedHeight)
            : collapsedSize
        let screenFrame = screen.frame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        panel.level = topWindowLevel
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: false)
        panel.orderFrontRegardless()
    }

    private func fadeIn() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return CGDisplayIsBuiltin(displayID) != 0
        }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}
