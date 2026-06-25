import AppKit
import JunimoCore
import SwiftUI

final class JunimoPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class NotchPanelController {
    private let coordinator: TaskCoordinator
    private let panel: JunimoPanel
    private let collapsedSize = NSSize(width: 236, height: 46)

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
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = false

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
    }

    func show() {
        resize(isExpanded: coordinator.isExpanded)
        panel.orderFrontRegardless()
    }

    func expandAndShow() {
        coordinator.pointerEntered()
        resize(isExpanded: true)
        panel.orderFrontRegardless()
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
            screenMaxY: Double(NSScreen.main?.frame.maxY ?? frame.maxY)
        )
    }

    private func resize(isExpanded: Bool) {
        let size = isExpanded
            ? NSSize(width: coordinator.preferences.expandedWidth, height: coordinator.preferences.expandedHeight)
            : collapsedSize
        guard let screen = NSScreen.main else {
            panel.setFrame(NSRect(origin: .zero, size: size), display: true, animate: true)
            return
        }

        let screenFrame = screen.frame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height - CGFloat(coordinator.preferences.topOffset)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: true)
    }
}
