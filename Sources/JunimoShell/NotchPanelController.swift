import AppKit
import Combine
import CoreGraphics
import JunimoCore
import QuartzCore
import SwiftUI

final class JunimoPanel: NSPanel {
    // 可成为 key window 以保持快捷按钮交互；它仍不是主窗口。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class NotchHostingView: NSHostingView<JunimoSurfaceView> {
    override func menu(for event: NSEvent) -> NSMenu? {
        super.menu(for: event) ?? menu
    }
}

@MainActor
final class NotchPanelController {
    private let state: ShellState
    private let quickLaunchStore: QuickLaunchConfigurationStore
    private let panel: JunimoPanel
    private var laneWidth = JunimoPanelLayout.collapsedCapsuleLaneWidth(showsAntigravity: false)
    private var laneObservation: AnyCancellable?
    private let expandedSize = NSSize(
        width: JunimoPanelLayout.expandedWidth,
        height: JunimoPanelLayout.expandedHeight
    )
    private let topWindowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
    private var screenChangeObserver: NSObjectProtocol?

    var isVisible: Bool {
        panel.isVisible
    }

    convenience init(state: ShellState, menu: NSMenu) {
        self.init(state: state, menu: menu, quickLaunchStore: QuickLaunchConfigurationStore())
    }

    init(state: ShellState, menu: NSMenu, quickLaunchStore: QuickLaunchConfigurationStore) {
        self.state = state
        self.quickLaunchStore = quickLaunchStore
        quickLaunchStore.start()
        panel = JunimoPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.level = topWindowLevel
        panel.contentView = NotchHostingView(
            rootView: JunimoSurfaceView(state: state, quickLaunchStore: quickLaunchStore)
        )
        panel.contentView?.menu = menu

        state.expansionDidChange = { [weak self] expanded in
            // ShellState 已在主线程；同步调整窗口，避免大视图先在旧 frame 中短暂绘制。
            self?.resize(expanded: expanded)
        }

        laneObservation = state.$surfaceState
            .map { JunimoPanelLayout.collapsedCapsuleLaneWidth(showsAntigravity: $0.showsAntigravity) }
            .removeDuplicates()
            .sink { [weak self] width in
                guard let self, laneWidth != width else { return }
                laneWidth = width
                if !state.isExpanded { resize(expanded: false) }
            }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.resize(expanded: self.state.isExpanded)
                self.panel.orderFrontRegardless()
            }
        }
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    func show() {
        let shouldFadeIn = !panel.isVisible
        resize(expanded: state.isExpanded)
        if shouldFadeIn {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        if shouldFadeIn {
            fadeIn()
        }
    }

    func expandAndShow() {
        state.expand()
        show()
    }

    func stop() {
        quickLaunchStore.stop()
        panel.orderOut(nil)
    }

    func openQuickLaunchConfiguration() {
        quickLaunchStore.reloadFromDisk()
        NSWorkspace.shared.open(quickLaunchStore.fileURL)
    }

    private func resize(expanded: Bool) {
        guard let screen = targetScreen() else {
            panel.setFrame(NSRect(origin: .zero, size: size(on: nil, expanded: expanded)), display: true, animate: false)
            return
        }
        if let host = panel.contentView as? NSHostingView<JunimoSurfaceView> {
            let clearance = JunimoScreenGeometry.notchClearance(on: screen)
            if host.rootView.notchClearance != clearance { host.rootView.notchClearance = clearance }
        }
        let frame = panelFrame(on: screen, expanded: expanded)
        panel.level = topWindowLevel
        panel.setFrame(frame, display: true, animate: false)
    }

    private func panelFrame(on screen: NSScreen, expanded: Bool) -> NSRect {
        let screenFrame = screen.frame
        let size = size(on: screen, expanded: expanded)
        return NSRect(
            x: expanded ? screenFrame.midX - size.width / 2 : screenFrame.midX - JunimoScreenGeometry.notchClearance(on: screen) - laneWidth,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func size(on screen: NSScreen?, expanded: Bool) -> NSSize {
        guard !expanded else { return expandedSize }
        guard let screen else {
            return NSSize(width: laneWidth + JunimoPanelLayout.collapsedNotchClearance * 2, height: NotchPanelMetrics.minimumCollapsedHeight)
        }
        return NSSize(
            width: laneWidth + JunimoScreenGeometry.notchClearance(on: screen) * 2,
            height: NotchPanelMetrics.collapsedHeight(
                screenTop: screen.frame.maxY,
                visibleTop: screen.visibleFrame.maxY
            )
        )
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
