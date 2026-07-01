import AppKit
import CoreGraphics
import JunimoCore
import QuartzCore
import SwiftUI

final class CornerNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class CornerNotePanelController {
    private let coordinator: TaskCoordinator
    private let panel: CornerNotePanel
    private let collapsedSize = CornerNoteLayout.triggerSize
    private let expandedSize = CornerNoteLayout.expandedWindowSize
    private let panelLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
    private var screenChangeObserver: NSObjectProtocol?
    private var hoverWorkItem: DispatchWorkItem?

    init(coordinator: TaskCoordinator) {
        self.coordinator = coordinator
        panel = CornerNotePanel(
            contentRect: .zero,
            styleMask: [.borderless],
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
        panel.level = panelLevel

        let view = CornerNoteSurfaceView(
            coordinator: coordinator,
            onTriggerHoverChanged: { [weak self] isInside in
                isInside ? self?.scheduleExpansion() : self?.cancelExpansion()
            },
            onTriggerTapped: { [weak self] in
                self?.expandAndShow()
            }
        )
        panel.contentView = NSHostingView(rootView: view)

        coordinator.cornerNoteExpansionDidChange = { [weak self] isExpanded in
            DispatchQueue.main.async {
                self?.resize(isExpanded: isExpanded)
            }
        }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.pinToBottomRight(isExpanded: self.coordinator.isCornerNoteExpanded)
        }
    }

    deinit {
        cancelExpansion()
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    func show() {
        resize(isExpanded: coordinator.isCornerNoteExpanded)
        panel.orderFrontRegardless()
        pinToBottomRight(isExpanded: coordinator.isCornerNoteExpanded)
    }

    func expandAndShow() {
        cancelExpansion()
        coordinator.setCornerNoteExpanded(true)
        panel.level = panelLevel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func collapse() {
        cancelExpansion()
        coordinator.setCornerNoteExpanded(false)
    }

    private func scheduleExpansion() {
        guard !coordinator.isCornerNoteExpanded else {
            return
        }
        cancelExpansion()
        let workItem = DispatchWorkItem { [weak self] in
            self?.coordinator.setCornerNoteExpanded(true)
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func cancelExpansion() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
    }

    private func resize(isExpanded: Bool) {
        let size = isExpanded ? expandedSize : collapsedSize
        panel.hasShadow = isExpanded
        guard let screen = targetScreen() else {
            panel.setFrame(NSRect(origin: .zero, size: size), display: true, animate: false)
            return
        }

        let frame = frameForPanel(size: size, on: screen)
        panel.level = panelLevel
        panel.setFrame(frame, display: true, animate: false)
        if isExpanded {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func pinToBottomRight(isExpanded: Bool) {
        guard let screen = targetScreen() else {
            return
        }
        let size = isExpanded ? expandedSize : collapsedSize
        panel.hasShadow = isExpanded
        panel.level = panelLevel
        panel.setFrame(frameForPanel(size: size, on: screen), display: true, animate: false)
        panel.orderFrontRegardless()
    }

    private func frameForPanel(size: NSSize, on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        return NSRect(
            x: visibleFrame.maxX - size.width,
            y: visibleFrame.minY,
            width: size.width,
            height: size.height
        )
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
