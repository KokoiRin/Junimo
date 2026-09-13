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
    func selectAppShortcut(_ request: AppShortcutSelectionRequest) async throws -> AppShortcut? {
        throw AppShortcutError.message("视觉测试不执行应用切换")
    }
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

// 八个收藏在右侧布局中应保持圆角外透明和足够可见图标，前台高亮必须改变图像且长名称不得撑宽胶囊，旧的下方位置设置应被清除。
@MainActor
func testAppBarLayoutAndActiveHighlight() async {
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
    defaults.set("below", forKey: "appBar.placement")
    let presentation = AppBarPresentation(defaults: defaults)
    guard defaults.object(forKey: "appBar.placement") == nil else { fail("obsolete placement preference must be removed") }
    presentation.refreshApplications(store.items)
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/app-bar-previews")
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    presentation.activeBundleID = nil
    let capacity = AppBarCapacity(count: store.items.count, availableWidth: presentation.availableWidth)
    let size = CGSize(width: capacity.width, height: AppBarLayout.cellSize)
    let view = AppBarView(store: store, presentation: presentation, open: { _ in fail("render must not open apps") }, manage: {})
    let idle = render(view.frame(width: size.width, height: size.height), size: size)
    presentation.activeBundleID = store.items.first?.bundleId
    let active = render(view.frame(width: size.width, height: size.height), size: size)
    guard alpha(active, at: CGPoint(x: 0, y: 0), size: size) < 0.15 else { fail("capsule corner must be transparent") }
    guard alpha(active, at: CGPoint(x: size.width / 2, y: size.height / 2), size: size) > 0.9 else { fail("app bar center must be visible") }
    guard active.tiffRepresentation != idle.tiffRepresentation else { fail("frontmost app must have a visible highlight") }
    if let png = active.representation(using: .png, properties: [:]) {
        try? png.write(to: output.appendingPathComponent("right.png"))
    }
    let manager = render(AppShortcutManagerView(store: store, presentation: presentation, add: {}), size: CGSize(width: 460, height: 370))
    if let png = manager.representation(using: .png, properties: [:]) {
        try? png.write(to: output.appendingPathComponent("manager.png"))
    }
    // 用户关闭应用栏后，新建外壳偏好对象必须恢复关闭状态。
    presentation.toggle()
    let restored = AppBarPresentation(defaults: defaults)
    guard !restored.enabled else { fail("shell preferences must survive recreation") }
}

// 真实独立面板在收藏加载后出现，展开主面板和关闭开关时隐藏，折叠、重新开启后恢复，清空收藏后再次隐藏。
@MainActor
func testAppBarWindowVisibility() async {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let suite = "junimo-window-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let presentation = AppBarPresentation(defaults: defaults)
    let backend = VisualShortcutsBackend()
    let state = ShellState()
    let controller = AppBarController(state: state, backend: backend, presentation: presentation, enableGlobalGestures: false)
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

func swipeEvent(x: Int32, y: Int32 = 0, phase: Int64 = 2, momentum: Int64 = 0,
                command: Bool = true, precise: Bool = true) -> NSEvent {
    let raw = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                      wheel1: y, wheel2: x, wheel3: 0)!
    raw.flags = command ? .maskCommand : []
    raw.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
    raw.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    raw.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    return NSEvent(cgEvent: raw)!
}

// Command 横滑累计越过阈值后只触发一次，松开 Command 后的惯性仍被消费，下一次反向手势可以再次切换。
func testCommandSwipeConsumesOneGesture() {
    var recognizer = AppBarSwipeRecognizer()
    let first = recognizer.handle(swipeEvent(x: -10, phase: 1), enabled: true)
    guard first.consume && first.direction == nil else { fail("small horizontal motion should be captured without switching") }
    let next = recognizer.handle(swipeEvent(x: -20), enabled: true)
    guard next.consume && next.direction == 1 else { fail("horizontal threshold should select the next icon") }
    guard recognizer.handle(swipeEvent(x: -80), enabled: true).direction == nil else { fail("one gesture must switch only once") }
    _ = recognizer.handle(swipeEvent(x: 0, phase: 4), enabled: true)
    for phase: Int64 in [1, 2, 3] {
        let inertia = recognizer.handle(swipeEvent(x: -80, phase: 0, momentum: phase, command: false), enabled: true)
        guard inertia.consume && inertia.direction == nil else { fail("momentum must not leak or switch again") }
    }
    guard recognizer.handle(swipeEvent(x: 30, phase: 1), enabled: true).direction == -1 else {
        fail("a new reverse gesture should select the previous icon")
    }
}

// 普通滚动、Command 竖滑、鼠标滚轮和不可切换的面板都不拦截，滚动中途按 Command 或取消手势也不能切应用。
func testCommandSwipeLeavesOtherInputAlone() {
    for event in [swipeEvent(x: -40, phase: 1, command: false), swipeEvent(x: 0, y: -40, phase: 1),
                  swipeEvent(x: -40, phase: 0, precise: false)] {
        var recognizer = AppBarSwipeRecognizer()
        let result = recognizer.handle(event, enabled: true)
        guard !result.consume && result.direction == nil else { fail("unrelated scrolling must pass through") }
    }
    var disabled = AppBarSwipeRecognizer()
    guard !disabled.handle(swipeEvent(x: -40, phase: 1), enabled: false).consume else { fail("disabled bar must not intercept") }
    var lateCommand = AppBarSwipeRecognizer()
    _ = lateCommand.handle(swipeEvent(x: -10, phase: 1, command: false), enabled: true)
    guard !lateCommand.handle(swipeEvent(x: -40), enabled: true).consume else { fail("Command pressed during scrolling must not capture it") }
    var cancelled = AppBarSwipeRecognizer()
    _ = cancelled.handle(swipeEvent(x: -10, phase: 1), enabled: true)
    guard cancelled.handle(swipeEvent(x: -50, phase: 8), enabled: true).direction == nil else { fail("cancelled gesture must not switch") }
}

@MainActor
final class FakeSwipeAccess: AppBarSwipeAccess {
    var trusted = false
    var isRunning = false
    var canInstall = true
    var prompted = false
    var generation = 0
    func isTrusted(prompt: Bool) -> Bool { prompted = prompted || prompt; return trusted }
    func install(handler: @escaping (NSEvent) -> Bool) -> Bool {
        generation += 1
        isRunning = canInstall
        return isRunning
    }
    func remove() { isRunning = false }
}

// 未授权时记录缺少权限且不弹窗，用户授权后自动连接；失效的监听可自动重建，撤销授权后停止监听，只有主动授权才触发系统提示。
@MainActor
func testSwipePermissionRecovery() {
    let access = FakeSwipeAccess()
    let monitor = AppBarSwipeMonitor(access: access)
    monitor.start()
    guard monitor.status == .needsPermission && access.generation == 0 && !access.prompted else { fail("permission polling must not prompt or install") }
    monitor.start(prompt: true)
    guard access.prompted && monitor.status == .needsPermission else { fail("requesting permission must not assume a grant") }
    access.trusted = true
    monitor.start()
    guard monitor.isRunning && access.generation == 1 else { fail("grant should automatically connect") }
    monitor.start()
    guard access.generation == 1 else { fail("healthy connection should be reused") }
    access.isRunning = false
    monitor.start()
    guard monitor.isRunning && access.generation == 2 else { fail("disabled tap must be replaced") }
    access.trusted = false
    monitor.start()
    guard monitor.status == .needsPermission && !access.isRunning else { fail("revoked grant must stop interception") }
    access.trusted = true
    access.canInstall = false
    monitor.start()
    guard monitor.status == .unavailable else { fail("tap failure must not be mistaken for missing permission") }
    access.canInstall = true
    monitor.start()
    guard monitor.isRunning else { fail("transient failure should recover without user action") }
    monitor.stop()
    guard monitor.status == .stopped && !access.isRunning else { fail("stop must release the listener") }
}

Task { @MainActor in
    testSwipePermissionRecovery()
    testCommandSwipeConsumesOneGesture()
    testCommandSwipeLeavesOtherInputAlone()
    await testApplicationReopenIncludesFrontmostApplication()
    await testAppBarLayoutAndActiveHighlight()
    await testAppBarWindowVisibility()
    testExpandedPanelKeepsRoundedCornersTransparent()
    testCompanionRendersVisibleAccentContent()
    testCompanionKeepsReadableTypography()
    testCollapsedControlsKeepNotchTriggerClear()
    print("Junimo companion visual regression tests passed")
    exit(0)
}
RunLoop.main.run()
