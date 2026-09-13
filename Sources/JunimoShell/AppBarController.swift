import AppKit
import Combine
import CoreGraphics
import JunimoCore
import SwiftUI
import UniformTypeIdentifiers

// 独立面板不激活 Junimo；只在胶囊轮廓内接收鼠标，圆角外保留底层点击。
final class AppBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppBarController: NSObject {
    let store: AppShortcutsStore
    let presentation: AppBarPresentation
    var isVisible: Bool { panel.isVisible }
    var windowNumber: Int { panel.windowNumber }
    private let state: ShellState
    private let panel: AppBarPanel
    private let workspace = MacQuickLaunchWorkspace()
    private let backend: AppShortcutsBackend
    private let swipeMonitor = AppBarSwipeMonitor()
    private let enableGlobalGestures: Bool
    private var swipeTask: Task<Void, Never>?
    private var swipeEnabled = UserDefaults.standard.object(forKey: "appBar.commandSwipe") as? Bool ?? true
    var swipeMenuTitle: String {
        if !swipeEnabled { return "启用 Command＋双指滑动切换" }
        return swipeMonitor.isRunning ? "关闭 Command＋双指滑动切换" : "恢复 Command＋双指滑动切换…"
    }
    private var manager: NSWindow?
    private var observations: Set<AnyCancellable> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var stopped = false
    private var geometryTimer: Timer?
    private var errorPopover: NSPopover?
    private var errorTask: Task<Void, Never>?
    private var activationTasks: [UUID: Task<Void, Never>] = [:]

    init(state: ShellState, backend: AppShortcutsBackend, presentation: AppBarPresentation? = nil,
         enableGlobalGestures: Bool = true) {
        self.state = state
        self.backend = backend
        self.enableGlobalGestures = enableGlobalGestures
        self.presentation = presentation ?? AppBarPresentation()
        store = AppShortcutsStore(backend: backend)
        panel = AppBarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        swipeMonitor.canSwitch = { [weak self] in
            guard let self else { return false }
            return self.panel.isVisible && self.store.isLoaded && self.visibleItems.count > 1
                && self.manager?.isVisible != true
        }
        swipeMonitor.switchDirection = { [weak self] in self?.switchApplication(direction: $0) }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        panel.contentView = NSHostingView(rootView: AppBarView(store: store, presentation: self.presentation,
            open: { [weak self] in self?.open($0) }, manage: { [weak self] in self?.showManager() },
            showMore: { [weak self] in self?.showMore($0) }))
        store.$items.sink { [weak self] items in
            // @Published 在赋值前投递，布局延后到主线程下一轮以读取已确认列表。
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.presentation.refreshApplications(items)
                self.updateLayout()
            }
        }.store(in: &observations)
        self.presentation.$placement.combineLatest(self.presentation.$enabled, state.$isExpanded)
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.updateLayout() } }
            .store(in: &observations)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.presentation.refreshApplications(self.store.items)
                    self.updateLayout()
                }
            })
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateLayout() }
            }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMousePassthrough() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.updateMousePassthrough() }
            return event
        }
        geometryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLayout() }
        }
        store.start()
    }

    func stop() {
        stopped = true
        swipeMonitor.stop()
        swipeTask?.cancel()
        swipeTask = nil
        geometryTimer?.invalidate()
        geometryTimer = nil
        store.stop()
        errorTask?.cancel()
        for task in activationTasks.values { task.cancel() }
        activationTasks.removeAll()
        observations.removeAll()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        errorPopover?.close()
        manager?.orderOut(nil)
        panel.orderOut(nil)
    }

    func toggleCommandSwipe() {
        if swipeEnabled && swipeMonitor.isRunning {
            swipeEnabled = false
            swipeMonitor.stop()
            swipeTask?.cancel()
        } else {
            swipeEnabled = true
            swipeMonitor.start(prompt: true)
            if swipeMonitor.status == .needsPermission,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                if !NSWorkspace.shared.open(url) {
                    showError("无法打开系统设置，请手动进入隐私与安全性 → 辅助功能。")
                }
            }
        }
        UserDefaults.standard.set(swipeEnabled, forKey: "appBar.commandSwipe")
    }

    private var visibleItems: [AppShortcut] {
        let capacity = AppBarCapacity(count: store.items.count, placement: presentation.placement,
                                      availableWidth: presentation.availableWidth)
        return Array(store.items.prefix(capacity.visibleCount))
    }

    private func switchApplication(direction: Int) {
        guard swipeTask == nil, activationTasks.isEmpty else { return }
        let items = visibleItems
        let revision = store.revision
        let activeID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        swipeTask = Task { [weak self] in
            guard let self else { return }
            defer { swipeTask = nil }
            do {
                let target = try await backend.selectAppShortcut(AppShortcutSelectionRequest(
                    revision: revision, visibleCount: items.count, activeId: activeID, direction: direction))
                // 等待后端期间若用户换了前台应用、收藏或布局，不执行过时的打开动作。
                guard !Task.isCancelled, panel.isVisible, store.revision == revision, visibleItems == items,
                      (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") == activeID,
                      let target, items.contains(target) else { return }
                try await workspace.activateApplication(bundleIdentifier: target.bundleId)
                presentation.refreshApplications(store.items)
            } catch {
                if !Task.isCancelled { showError("切换失败：\(error.localizedDescription)") }
            }
        }
    }

    func showManager() {
        presentation.error = nil
        if manager == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 410),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "管理常用应用"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AppShortcutManagerView(store: store, presentation: presentation,
                add: { [weak self] in self?.chooseApplications() }))
            window.center()
            manager = window
        }
        state.pointerExited()
        NSApp.activate(ignoringOtherApps: true)
        manager?.makeKeyAndOrderFront(nil)
    }

    private func showMore(_ items: [AppShortcut]) {
        guard let view = panel.contentView else { return }
        let menu = NSMenu()
        for item in items {
            let entry = NSMenuItem(title: item.name, action: #selector(openFromMenu(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.bundleId
            entry.image = presentation.icons[item.bundleId]
            entry.state = presentation.activeBundleID == item.bundleId ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let manage = NSMenuItem(title: "管理常用应用…", action: #selector(manageFromMenu), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)
        menu.popUp(positioning: nil, at: NSPoint(x: max(0, view.bounds.width - 34), y: view.bounds.maxY), in: view)
    }
    @objc private func openFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let item = store.items.first(where: { $0.id == id }) else { return }
        open(item)
    }
    @objc private func manageFromMenu() { showManager() }

    private func chooseApplications() {
        guard let manager else { return }
        let picker = NSOpenPanel()
        picker.title = "选择常用应用"
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.beginSheetModal(for: manager) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, response == .OK else { return }
                var proposed = self.store.items
                for url in picker.urls {
                    guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
                        self.presentation.error = "所选应用缺少有效的应用标识。"
                        return
                    }
                    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? url.deletingPathExtension().lastPathComponent
                    proposed.append(AppShortcut(bundleId: identifier, name: name))
                }
                self.presentation.error = nil
                let revision = self.store.revision
                Task { await self.store.save(proposed, basedOn: revision) }
            }
        }
    }

    private func open(_ item: AppShortcut) {
        swipeTask?.cancel()
        errorPopover?.close()
        state.pointerExited()
        let id = UUID()
        activationTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { activationTasks.removeValue(forKey: id) }
            do { try await workspace.activateApplication(bundleIdentifier: item.bundleId) }
            catch { if !Task.isCancelled { showError("无法打开 \(item.name)：\(error.localizedDescription)") } }
        }
    }

    private func showError(_ message: String) {
        presentation.error = message
        guard panel.isVisible, let view = panel.contentView else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        let controller = NSViewController()
        controller.view = NSHostingView(rootView: Text(message).font(.callout).padding(12).frame(width: 280))
        popover.contentViewController = controller
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        errorPopover = popover
        errorTask?.cancel()
        errorTask = Task { [weak popover] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { popover?.close() }
        }
    }

    private func updateLayout() {
        guard !stopped else { return }
        if enableGlobalGestures && swipeEnabled { swipeMonitor.start() }
        guard presentation.enabled, !state.isExpanded, !store.items.isEmpty,
              let screen = JunimoScreenGeometry.targetScreen() else {
            errorPopover?.close()
            panel.orderOut(nil)
            return
        }
        let placement = presentation.placement
        let originX: CGFloat
        let originY: CGFloat
        let available: CGFloat
        if placement == .right {
            // 主面板可能保留比物理刘海更宽的净空，应用栏必须避开整个悬停窗口。
            originX = max(JunimoScreenGeometry.notchRight(on: screen) + 6,
                          screen.frame.midX + JunimoScreenGeometry.notchClearance(on: screen) + 4)
            // 系统不公开“菜单栏空闲区域”，保守预留右侧状态区，并进一步避开可读到的状态窗口。
            let boundary = JunimoScreenGeometry.statusBoundary(on: screen, after: originX)
            available = min(158, max(0, boundary - originX - 8))
            let height = max(placement.cellSize, screen.safeAreaInsets.top)
            originY = screen.frame.maxY - height + (height - placement.cellSize) / 2
        } else {
            available = min(260, screen.frame.width - 24)
            originX = screen.frame.midX
            originY = screen.frame.maxY - max(28, screen.safeAreaInsets.top) - placement.cellSize - 4
        }
        if presentation.availableWidth != available { presentation.availableWidth = available }
        let capacity = AppBarCapacity(count: store.items.count, placement: placement, availableWidth: available)
        guard capacity.width > 0 else { panel.orderOut(nil); return }
        let x = placement == .right ? originX : originX - capacity.width / 2
        let frame = NSRect(x: x, y: originY, width: capacity.width, height: placement.cellSize)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        updateMousePassthrough()
    }

    private func updateMousePassthrough() {
        let point = NSEvent.mouseLocation
        let local = NSPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: panel.frame.size),
                                xRadius: panel.frame.height / 2, yRadius: panel.frame.height / 2)
        panel.ignoresMouseEvents = !path.contains(local)
    }
}

@MainActor
enum JunimoScreenGeometry {
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
    static func notchRight(on screen: NSScreen) -> CGFloat {
        if let area = screen.auxiliaryTopRightArea { return area.minX }
        return screen.frame.midX + JunimoPanelLayout.collapsedNotchClearance
    }
    static func notchClearance(on screen: NSScreen) -> CGFloat {
        max(JunimoPanelLayout.collapsedNotchClearance, notchRight(on: screen) - screen.frame.midX + 6)
    }
    static func statusBoundary(on screen: NSScreen, after x: CGFloat) -> CGFloat {
        var boundary = screen.frame.maxX - 280
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return boundary }
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != getpid(),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= Int(CGWindowLevelForKey(.statusWindow)),
                  let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary) else { continue }
            let rect = CGRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
            guard rect.height <= 64, rect.width < screen.frame.width / 2,
                  rect.maxY >= screen.frame.maxY - 40, rect.minY < screen.frame.maxY,
                  rect.maxX > x, rect.minX < screen.frame.maxX else { continue }
            boundary = min(boundary, max(x, rect.minX))
        }
        return boundary
    }
}
