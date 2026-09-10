import AppKit
import JunimoCore
import SwiftUI

func fail(_ message: String) -> Never {
    fputs("Visual test failed: \(message)\n", stderr)
    exit(1)
}

final class VisualFakeWorkspace: QuickLaunchOpening {
    func openApplication(bundleIdentifier: String) -> Bool { true }
    func openURL(_ url: URL) -> Bool { true }
}

// 展开真实 companion 时中心必须不透明，且仅底部两个圆角外侧保持透明。
@MainActor
func testExpandedPanelKeepsRoundedCornersTransparent() {
    let hostSize = CGSize(width: 640, height: 380)
    let panelSize = CGSize(width: JunimoPanelLayout.expandedWidth, height: JunimoPanelLayout.expandedHeight)
    let panelOrigin = CGPoint(
        x: (hostSize.width - panelSize.width) / 2,
        y: (hostSize.height - panelSize.height) / 2
    )
    let state = ShellState()
    state.pointerEntered()
    let view = ZStack {
        Color.clear
        JunimoSurfaceView(
            state: state,
            launcher: QuickLauncher(workspace: VisualFakeWorkspace())
        )
    }
    .frame(width: hostSize.width, height: hostSize.height)
    let bitmap = render(view, size: hostSize)

    let centerAlpha = alpha(bitmap, at: CGPoint(x: hostSize.width / 2, y: hostSize.height / 2), size: hostSize)
    guard centerAlpha > 0.95 else {
        fail("expanded panel center should be opaque, alpha was \(centerAlpha)")
    }

    let inset: CGFloat = 3
    let corners = [
        CGPoint(x: panelOrigin.x + inset, y: panelOrigin.y + inset),
        CGPoint(x: panelOrigin.x + panelSize.width - inset, y: panelOrigin.y + inset),
        CGPoint(x: panelOrigin.x + inset, y: panelOrigin.y + panelSize.height - inset),
        CGPoint(x: panelOrigin.x + panelSize.width - inset, y: panelOrigin.y + panelSize.height - inset)
    ]
    let transparent = corners.filter { alpha(bitmap, at: $0, size: hostSize) < 0.02 }
    guard transparent.count == 2 else {
        fail("exactly two rounded corners should be transparent")
    }
}

// 单一 companion 面板应绘制足量可见内容和绿色强调元素，防止布局退化为空壳或全透明表面。
@MainActor
func testCompanionRendersVisibleAccentContent() {
    let size = CGSize(width: JunimoPanelLayout.expandedWidth, height: JunimoPanelLayout.expandedHeight)
    let state = ShellState()
    state.pointerEntered()
    let bitmap = render(
        JunimoSurfaceView(
            state: state,
            launcher: QuickLauncher(workspace: VisualFakeWorkspace())
        ).frame(width: size.width, height: size.height),
        size: size
    )

    var accentPixels = 0
    var visiblePixels = 0
    for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            guard let source = bitmap.colorAt(x: x, y: y),
                  let color = source.usingColorSpace(.deviceRGB) else { continue }
            if color.greenComponent > 0.70 && color.redComponent < 0.55 {
                accentPixels += 1
            }
            if color.alphaComponent > 0.9 && max(color.redComponent, color.greenComponent, color.blueComponent) > 0.08 {
                visiblePixels += 1
            }
        }
    }
    guard accentPixels > 20 else { fail("companion should render green activity and shortcut accents") }
    guard visiblePixels > 100 else { fail("companion should render visible usage and shortcut content") }
}

// 轻量面板的标题和说明文字应维持清晰字号下限。
func testCompanionKeepsReadableTypography() {
    guard JunimoTypography.pageTitle >= 22 else { fail("title should remain at least 22pt") }
    guard JunimoTypography.caption >= 12 else { fail("caption should remain at least 12pt") }
}

// 折叠态应在刘海左侧画出用量胶囊、中央触发区保持视觉透明，右侧交给独立应用栏而不保留旧入口。
@MainActor
func testCollapsedControlsKeepNotchTriggerClear() {
    let size = CGSize(width: JunimoPanelLayout.collapsedCapsuleLaneWidth + JunimoPanelLayout.collapsedNotchClearance * 2, height: 33)
    let state = ShellState()
    let bitmap = render(
        JunimoSurfaceView(state: state, launcher: QuickLauncher(workspace: VisualFakeWorkspace()))
            .frame(width: size.width, height: size.height),
        size: size
    )
    let scale = CGFloat(bitmap.pixelsWide) / size.width
    let leftEnd = Int(JunimoPanelLayout.collapsedCapsuleLaneWidth * scale)
    let rightStart = Int(
        (JunimoPanelLayout.collapsedCapsuleLaneWidth + JunimoPanelLayout.collapsedNotchClearance * 2) * scale
    )
    var leftVisible = 0
    var centerVisible = 0
    var rightVisible = 0
    for x in 0..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh {
            guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.60 else { continue }
            if x < leftEnd {
                leftVisible += 1
            } else if x < rightStart {
                centerVisible += 1
            } else {
                rightVisible += 1
            }
        }
    }
    guard leftVisible > 20 else { fail("collapsed shell should render the usage capsule on the left") }
    guard rightVisible == 0 else { fail("collapsed shell must not retain the old launcher") }
    guard centerVisible == 0 else { fail("the notch hover trigger should remain visually transparent") }
}

@MainActor
func render<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.wantsLayer = true
    hosting.layer?.backgroundColor = NSColor.clear.cgColor
    hosting.layoutSubtreeIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        fail("could not allocate offscreen bitmap")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    return bitmap
}

func alpha(_ bitmap: NSBitmapImageRep, at point: CGPoint, size: CGSize) -> CGFloat {
    let x = min(bitmap.pixelsWide - 1, max(0, Int(point.x * CGFloat(bitmap.pixelsWide) / size.width)))
    let y = min(bitmap.pixelsHigh - 1, max(0, Int(point.y * CGFloat(bitmap.pixelsHigh) / size.height)))
    return bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
}

final class VisualShortcutsBackend: AppShortcutsBackend {
    var items: [AppShortcut] = [
        AppShortcut(bundleId: "com.openai.codex", name: "Codex — 一个很长的应用名称也不应该撑宽图标栏"),
        AppShortcut(bundleId: "com.apple.finder", name: "Finder"),
        AppShortcut(bundleId: "com.google.Chrome", name: "Chrome"),
        AppShortcut(bundleId: "com.microsoft.VSCode", name: "Visual Studio Code"),
        AppShortcut(bundleId: "com.apple.Safari", name: "Safari"),
        AppShortcut(bundleId: "com.apple.Terminal", name: "Terminal"),
        AppShortcut(bundleId: "com.test.missing", name: "未安装的应用"),
        AppShortcut(bundleId: "com.test.more", name: "更多应用")
    ]
    var revision: UInt64 = 1
    func loadAppShortcuts() async throws -> AppShortcutList { AppShortcutList(items: items, revision: revision) }
    func saveAppShortcuts(_ items: [AppShortcut], revision: UInt64) async throws -> AppShortcutList {
        guard revision == self.revision else { throw AppShortcutError.conflict }
        self.items = items
        self.revision += 1
        return AppShortcutList(items: items, revision: self.revision)
    }
}

// 同一组八个收藏在两种布局中都应保持圆角外透明和足够可见图标，前台高亮必须改变图像且长名称不得撑宽胶囊。
@MainActor
func testAppBarLayoutsAndActiveHighlight() async {
    let store = AppShortcutsStore(backend: VisualShortcutsBackend())
    store.start()
    for _ in 0..<100 {
        if store.isLoaded { break }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    guard store.isLoaded else { fail("visual fixture failed to load") }
    let suite = "junimo-visual-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite); store.stop() }
    let presentation = AppBarPresentation(defaults: defaults)
    presentation.refreshApplications(store.items)
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/app-bar-previews")
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for placement in AppBarPlacement.allCases {
        presentation.placement = placement
        presentation.availableWidth = placement == .right ? 158 : 260
        presentation.activeBundleID = nil
        let capacity = AppBarCapacity(count: store.items.count, placement: placement, availableWidth: presentation.availableWidth)
        let size = CGSize(width: capacity.width, height: placement.cellSize)
        let view = AppBarView(store: store, presentation: presentation, open: { _ in fail("render must not open apps") }, manage: {})
        let idle = render(view.frame(width: size.width, height: size.height), size: size)
        presentation.activeBundleID = store.items.first?.bundleId
        let active = render(view.frame(width: size.width, height: size.height), size: size)
        guard alpha(active, at: CGPoint(x: 0, y: 0), size: size) < 0.15 else { fail("capsule corner must be transparent") }
        guard alpha(active, at: CGPoint(x: size.width / 2, y: size.height / 2), size: size) > 0.9 else { fail("app bar center must be visible") }
        guard active.tiffRepresentation != idle.tiffRepresentation else { fail("frontmost app must have a visible highlight") }
        if let png = active.representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("\(placement.rawValue).png"))
        }
    }
    let manager = render(AppShortcutManagerView(store: store, presentation: presentation, add: {}), size: CGSize(width: 460, height: 370))
    if let png = manager.representation(using: .png, properties: [:]) {
        try? png.write(to: output.appendingPathComponent("manager.png"))
    }
    // 用户切换位置并关闭应用栏后，新建外壳偏好对象必须恢复同样的选择。
    presentation.setPlacement(.below)
    presentation.toggle()
    let restored = AppBarPresentation(defaults: defaults)
    guard restored.placement == .below, !restored.enabled else { fail("shell preferences must survive recreation") }
}

// 真实独立面板在收藏加载后出现，展开主面板和关闭开关时隐藏，折叠、换位置后恢复，清空收藏后再次隐藏。
@MainActor
func testAppBarWindowVisibility() async {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let suite = "junimo-window-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let presentation = AppBarPresentation(defaults: defaults)
    presentation.setPlacement(.below)
    let backend = VisualShortcutsBackend()
    let state = ShellState()
    let controller = AppBarController(state: state, backend: backend, presentation: presentation)
    defer { controller.stop(); defaults.removePersistentDomain(forName: suite) }
    func waitFor(_ expected: Bool) async {
        for _ in 0..<100 {
            if controller.isVisible == expected { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        fail("app bar visibility should be \(expected)")
    }
    await waitFor(true)
    state.pointerEntered()
    await waitFor(false)
    state.pointerExited()
    await waitFor(true)
    presentation.toggle()
    await waitFor(false)
    presentation.setPlacement(.right)
    presentation.setPlacement(.below)
    presentation.toggle()
    await waitFor(true)
    await controller.store.save([], basedOn: controller.store.revision)
    await waitFor(false)
}

final class ReopenApplication: NSRunningApplication, @unchecked Sendable {
    override var bundleIdentifier: String? { "com.test.reopen" }
}

final class ReopenWorkspace: NSWorkspace {
    let app = ReopenApplication()
    var hasFrontmostApplication = true
    var requestedReopen = false
    var launchError: Error?
    override var frontmostApplication: NSRunningApplication? { hasFrontmostApplication ? app : nil }
    override func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        URL(fileURLWithPath: "/Applications/ReopenFixture.app")
    }
    override func openApplication(at applicationURL: URL, configuration: NSWorkspace.OpenConfiguration,
                                  completionHandler: ((NSRunningApplication?, Error?) -> Void)? = nil) {
        requestedReopen = configuration.activates && !configuration.createsNewApplicationInstance
        completionHandler?(app, launchError)
    }
}

// 应用即使已在前台也应收到系统 reopen 请求来恢复窗口；非前台应用同样激活已有实例，打开失败必须返回错误。
@MainActor
func testApplicationReopenIncludesFrontmostApplication() async {
    let workspace = ReopenWorkspace()
    let launcher = MacQuickLaunchWorkspace(workspace: workspace)
    for frontmost in [true, false] {
        workspace.hasFrontmostApplication = frontmost
        workspace.requestedReopen = false
        do { try await launcher.activateApplication(bundleIdentifier: "com.test.reopen") }
        catch { fail("reopen fixture unexpectedly failed: \(error)") }
        guard workspace.requestedReopen else { fail("frontmost and inactive apps must both receive reopen") }
    }
    workspace.launchError = NSError(domain: "ReopenFixture", code: 1)
    var failed = false
    do { try await launcher.activateApplication(bundleIdentifier: "com.test.reopen") }
    catch { failed = true }
    guard failed else { fail("launch errors must reach the caller") }
}

Task { @MainActor in
    await testApplicationReopenIncludesFrontmostApplication()
    await testAppBarLayoutsAndActiveHighlight()
    await testAppBarWindowVisibility()
    testExpandedPanelKeepsRoundedCornersTransparent()
    testCompanionRendersVisibleAccentContent()
    testCompanionKeepsReadableTypography()
    testCollapsedControlsKeepNotchTriggerClear()
    print("Junimo companion visual regression tests passed")
    exit(0)
}
RunLoop.main.run()
