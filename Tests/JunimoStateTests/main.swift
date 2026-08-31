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

Task { @MainActor in
    await testShellStateLoadsCompanionStateAndManagesHover()
    await testActivityFailureKeepsUsageVisible()
    await testShellStateRejectsOlderSnapshots()
    await testQuickLaunchConfigurationHotReloadKeepsLastGoodCatalog()
    print("Junimo ShellState companion tests passed")
    exit(0)
}
RunLoop.main.run()
