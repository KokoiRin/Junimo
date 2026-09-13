import Foundation
import JunimoCore

// FakeBackend 只模拟 v5 只读快照与生命周期，不重新实现 Go 产品逻辑。
final class FakeBackend: ShellBackendClient {
    private let lock = NSLock()
    private var states: [SurfaceState]
    private var stopped = false
    init(states: [SurfaceState] = [SurfaceState()]) {
        self.states = states
    }

    func start() async throws {}

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    func loadState() async throws -> SurfaceState {
        withLock {
            guard states.count > 1 else { return states[0] }
            return states.removeFirst()
        }
    }

    func wasStopped() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

func fail(_ message: String) -> Never {
    fputs("ShellState test failed: \(message)\n", stderr)
    exit(1)
}

@MainActor
func waitUntil(_ message: String, condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<150 {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    fail(message)
}

// 启动后壳层应加载只读 Codex 快照，hover 只产生一次展开/折叠变化，停止时释放后端。
@MainActor
func testShellStateLoadsCompanionStateAndManagesHover() async {
    let initial = SurfaceState(
        revision: 1,
        codex: CodexUsageSnapshot(
            status: .available,
            primary: CodexUsageWindow(remainingPercent: 80, windowDurationMinutes: 300)
        ),
        activity: CodexActivitySnapshot(status: .available)
    )
    let backend = FakeBackend(states: [initial])
    let state = ShellState(backend: backend)
    state.start()
    await waitUntil("start should load the v5 snapshot") {
        state.surfaceState == initial
    }

    var expansionChanges: [Bool] = []
    state.expansionDidChange = { expansionChanges.append($0) }
    state.pointerEntered()
    state.pointerEntered()
    state.pointerExited()
    if expansionChanges != [true, false] {
        fail("hover transitions = \(expansionChanges), want [true, false]")
    }

    state.stop()
    if !backend.wasStopped() {
        fail("stop should release the backend process")
    }
}

// activity 单独不可用时用量快照仍应保持可见，局部失败不能抹掉另一条产品事实。
@MainActor
func testActivityFailureKeepsUsageVisible() async {
    let snapshot = SurfaceState(
        revision: 1,
        codex: CodexUsageSnapshot(
            status: .available,
            primary: CodexUsageWindow(remainingPercent: 64, windowDurationMinutes: 300)
        ),
        activity: CodexActivitySnapshot(status: .unavailable, message: "activity unavailable")
    )
    let state = ShellState(backend: FakeBackend(states: [snapshot]))
    state.start()
    await waitUntil("activity failure should remain a partial state") {
        state.surfaceState.activity.status == .unavailable
    }
    if state.surfaceState.codex.compactSummary != "5h 64%" {
        fail("usage should remain visible when activity is unavailable")
    }
    state.stop()
}

// revision 2 已展示后再读到 revision 1 时，壳层不得让用量与完成事实倒退。
@MainActor
func testShellStateRejectsOlderSnapshots() async {
    let current = SurfaceState(
        revision: 2,
        codex: CodexUsageSnapshot(
            status: .available,
            primary: CodexUsageWindow(remainingPercent: 70, windowDurationMinutes: 300)
        )
    )
    let stale = SurfaceState(
        revision: 1,
        codex: CodexUsageSnapshot(
            status: .available,
            primary: CodexUsageWindow(remainingPercent: 10, windowDurationMinutes: 300)
        )
    )
    let state = ShellState(backend: FakeBackend(states: [current, stale]))
    state.start()
    await waitUntil("current snapshot should load") { state.surfaceState.revision == 2 }
    try? await Task.sleep(nanoseconds: 1_100_000_000)
    if state.surfaceState.revision != 2 || state.surfaceState.codex.compactSummary != "5h 70%" {
        fail("older revision must not replace the visible companion state")
    }
    state.stop()
}

// 首次启动应生成默认配置，普通原地保存和原子替换都应热更新，而损坏 JSON 只能报告错误并保留最后正确内容。
@MainActor
func testQuickLaunchConfigurationHotReloadKeepsLastGoodCatalog() async {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("junimo-quick-launch-\(UUID().uuidString)", isDirectory: true)
    let fileURL = root.appendingPathComponent("quick-launch.json")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = QuickLaunchConfigurationStore(fileURL: fileURL)
    store.start()
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        fail("start should create the editable quick-launch file")
    }
    guard store.commands.map(\.id) == ["codex"] else {
        fail("a new config should begin with the default catalog")
    }

    let changed = QuickLaunchConfiguration(items: [
        QuickLaunchItemConfiguration(
            id: "guide",
            title: "指南",
            icon: "reading",
            type: .url,
            target: "https://example.com/guide"
        )
    ])
    do {
        try QuickLaunchCatalog.encode(changed).write(to: fileURL)
    } catch {
        fail("writing a valid custom catalog failed: \(error)")
    }
    await waitUntil("saving the config should update the visible catalog without restart") {
        store.commands.map(\.id) == ["guide"]
    }

    do {
        try Data("{broken".utf8).write(to: fileURL, options: .atomic)
    } catch {
        fail("writing the invalid fixture failed: \(error)")
    }
    await waitUntil("invalid JSON should publish a configuration error") {
        store.lastErrorDescription != nil
    }
    if store.commands.map(\.id) != ["guide"] {
        fail("invalid JSON must keep the last good catalog")
    }

    let recovered = QuickLaunchConfiguration(items: [
        QuickLaunchItemConfiguration(
            id: "dashboard",
            title: "面板",
            icon: "data",
            type: .url,
            target: "https://example.com/dashboard"
        )
    ])
    do {
        try QuickLaunchCatalog.encode(recovered).write(to: fileURL, options: .atomic)
    } catch {
        fail("atomically replacing the config failed: \(error)")
    }
    await waitUntil("an atomic replacement should reconnect the file watcher and recover") {
        store.commands.map(\.id) == ["dashboard"] && store.lastErrorDescription == nil
    }
    store.stop()

    let restartedStore = QuickLaunchConfigurationStore(fileURL: fileURL)
    restartedStore.start()
    guard restartedStore.commands.map(\.id) == ["dashboard"] else {
        fail("restarting or updating the app must preserve an existing user catalog")
    }
    restartedStore.stop()
}

final class FakeShortcutsBackend: AppShortcutsBackend {
    func selectAppShortcut(_ request: AppShortcutSelectionRequest) async throws -> AppShortcut? {
        throw AppShortcutError.message("收藏保存测试不执行应用切换")
    }
    var value = AppShortcutList(items: [AppShortcut(bundleId: "com.test.one", name: "一")])
    var failSave = false
    var holdNextRead = false
    var pendingRead: CheckedContinuation<AppShortcutList, Error>?
    var capturedRead: AppShortcutList?
    func loadAppShortcuts() async throws -> AppShortcutList {
        if holdNextRead {
            holdNextRead = false
            capturedRead = value
            return try await withCheckedThrowingContinuation { pendingRead = $0 }
        }
        return value
    }
    func saveAppShortcuts(_ items: [AppShortcut], revision: UInt64) async throws -> AppShortcutList {
        if failSave { throw AppShortcutError.message("磁盘不可写") }
        guard revision == value.revision else { throw AppShortcutError.conflict }
        value = AppShortcutList(items: items, revision: value.revision + 1)
        return value
    }
}

// 后端拒绝保存时界面必须保留已确认收藏并展示错误，恢复后保存空列表应清空图标栏并消除错误。
@MainActor
func testAppShortcutsKeepConfirmedStateOnFailure() async {
    let backend = FakeShortcutsBackend()
    let store = AppShortcutsStore(backend: backend)
    store.start()
    await waitUntil("shortcuts should load") { store.isLoaded }
    backend.failSave = true
    await store.save([], basedOn: store.revision)
    guard store.items == backend.value.items, store.error != nil, !store.isSaving else {
        fail("failed save must preserve confirmed state")
    }
    backend.failSave = false
    await store.save([], basedOn: store.revision)
    guard store.items.isEmpty, store.error == nil else { fail("confirmed empty list must clear collection") }
    store.stop()
}

// 右侧只够四个槽位时应留一个更多入口，空间充足时最多展示四个应用，极窄区域应只显示更多或完全隐藏。
func testAppBarCapacityKeepsOverflowReachable() {
    let right = AppBarCapacity(count: 8, availableWidth: 128)
    guard right.visibleCount == 3, right.hasOverflow, right.width == 128 else { fail("overflow must fit right lane") }
    let full = AppBarCapacity(count: 8, availableWidth: 158)
    guard full.visibleCount == 4, full.hasOverflow, full.width == 158 else { fail("full right lane capacity incorrect") }
    let narrow = AppBarCapacity(count: 8, availableWidth: 38)
    guard narrow.visibleCount == 0, narrow.hasOverflow else { fail("narrow lane must retain more menu") }
    let absent = AppBarCapacity(count: 8, availableWidth: 20)
    let empty = AppBarCapacity(count: 0, availableWidth: 158)
    guard absent.width == 0, empty.width == 0 else { fail("empty or unavailable lane must disappear") }
}

// 外部更新应自动显示；基于旧版本提交的编辑应提示冲突且不丢失新收藏，按最新版本重试才能保存。
@MainActor
func testAppShortcutsRefreshAndRejectStaleEdits() async {
    let backend = FakeShortcutsBackend()
    let store = AppShortcutsStore(backend: backend, refreshIntervalNanoseconds: 10_000_000)
    store.start()
    defer { store.stop() }
    await waitUntil("initial collection should load") { store.isLoaded }
    let oldRevision = store.revision
    let oldItems = store.items
    backend.value = AppShortcutList(items: oldItems + [AppShortcut(bundleId: "com.google.Chrome", name: "Chrome")], revision: 2)
    await waitUntil("external collection should refresh automatically") { store.revision == 2 }
    guard store.items == backend.value.items else { fail("external app was not shown") }
    let android = AppShortcut(bundleId: "com.google.android.studio", name: "Android Studio")
    await store.save(oldItems + [android], basedOn: oldRevision)
    guard store.error != nil, store.items == backend.value.items, !backend.value.items.contains(android) else {
        fail("stale edit should be rejected without losing external changes")
    }
    await store.save(store.items + [android], basedOn: store.revision)
    guard store.items.map(\.name) == ["一", "Chrome", "Android Studio"], store.error == nil else { fail("fresh retry failed") }
}

// 轮询旧快照尚未返回时保存了新列表，迟到的旧响应不得让界面退回保存前的收藏或版本。
@MainActor
func testAppShortcutsIgnoreReadOlderThanSave() async {
    let backend = FakeShortcutsBackend()
    let store = AppShortcutsStore(backend: backend, refreshIntervalNanoseconds: 10_000_000)
    store.start()
    defer { store.stop() }
    await waitUntil("initial collection should load") { store.isLoaded }
    backend.holdNextRead = true
    await waitUntil("background read should be pending") { backend.pendingRead != nil }
    await store.save([], basedOn: store.revision)
    guard store.revision == 2 else { fail("new save should have revision two") }
    backend.pendingRead?.resume(returning: backend.capturedRead!)
    backend.pendingRead = nil
    try? await Task.sleep(nanoseconds: 30_000_000)
    guard store.items.isEmpty, store.revision == 2 else { fail("delayed read rolled back saved collection") }
}

Task { @MainActor in
    await testAppShortcutsRefreshAndRejectStaleEdits()
    await testAppShortcutsIgnoreReadOlderThanSave()
    await testAppShortcutsKeepConfirmedStateOnFailure()
    testAppBarCapacityKeepsOverflowReachable()
    await testShellStateLoadsCompanionStateAndManagesHover()
    await testActivityFailureKeepsUsageVisible()
    await testShellStateRejectsOlderSnapshots()
    await testQuickLaunchConfigurationHotReloadKeepsLastGoodCatalog()
    print("Junimo ShellState companion tests passed")
    exit(0)
}
RunLoop.main.run()
