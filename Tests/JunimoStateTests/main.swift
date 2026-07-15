import Foundation
import JunimoCore

// FakeBackendError 表示 Swift 壳层可观察的后端失败边界。
enum FakeBackendError: Error {
    case unavailable
}

// FakeBackend 记录壳层意图并提供确定的后端快照，不模拟 Go 状态机。
final class FakeBackend: ShellBackendClient {
    private let lock = NSLock()
    private var state: SurfaceState
    private var intents: [ProductIntent] = []
    private var stopped = false
    var failsToStart = false
    var failsIntents = false

    // 初始化 fake 当前可返回的组合快照。
    init(state: SurfaceState = SurfaceState()) {
        self.state = state
    }

    // 启动时按测试配置返回成功或不可用。
    func start() async throws {
        if failsToStart {
            throw FakeBackendError.unavailable
        }
    }

    // 记录壳层已经释放后端生命周期。
    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    // 返回最近一次可观察的后端快照。
    func loadState() async throws -> SurfaceState {
        withLock { state }
    }

    // 记录类型化意图并返回当前确定快照。
    func sendIntent(_ intent: ProductIntent) async throws -> SurfaceState {
        if failsIntents {
            throw FakeBackendError.unavailable
        }
        return withLock {
            intents.append(intent)
            return state
        }
    }

    // 返回壳层已经发送的全部类型化意图。
    func recordedIntents() -> [ProductIntent] {
        lock.lock()
        defer { lock.unlock() }
        return intents
    }

    // 返回后端生命周期是否已经被显式停止。
    func wasStopped() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    // withLock 保护 fake 在异步壳层任务中的可变测试状态。
    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

// OutOfOrderBackend 模拟意图新快照先返回、旧轮询快照后返回的真实 HTTP 时序。
final class OutOfOrderBackend: ShellBackendClient {
    private let lock = NSLock()
    private var loadCount = 0
    private var staleContinuation: CheckedContinuation<SurfaceState, Error>?

    // 启动不需要额外准备，测试只控制快照返回顺序。
    func start() async throws {}

    // 停止不拥有外部进程。
    func stop() {}

    // 首次返回 revision 1，第二次挂起 revision 2 的旧 running 轮询快照。
    func loadState() async throws -> SurfaceState {
        let currentLoad = nextLoadCount()
        if currentLoad == 1 {
            return SurfaceState(
                revision: 1,
                pomodoro: PomodoroSnapshot(mode: .focus, status: .running, remainingSeconds: 60)
            )
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            staleContinuation = continuation
            lock.unlock()
        }
    }

    // nextLoadCount 在同步 helper 内保护请求序号，避免在 async 上下文直接操作 NSLock。
    private func nextLoadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        loadCount += 1
        return loadCount
    }

    // pause 意图立即返回 revision 3，确保它比挂起的轮询快照更新。
    func sendIntent(_ intent: ProductIntent) async throws -> SurfaceState {
        guard intent == .pomodoro(.pause) else { throw FakeBackendError.unavailable }
        return SurfaceState(
            revision: 3,
            pomodoro: PomodoroSnapshot(mode: .focus, status: .paused, remainingSeconds: 60)
        )
    }

    // 暴露旧轮询请求是否已挂起，用于确定测试时序。
    func hasPendingStaleResponse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return staleContinuation != nil
    }

    // 在新意图快照生效后释放 revision 2，复现晚到旧响应。
    func releaseStaleResponse() {
        lock.lock()
        let continuation = staleContinuation
        staleContinuation = nil
        lock.unlock()
        continuation?.resume(returning: SurfaceState(
            revision: 2,
            pomodoro: PomodoroSnapshot(mode: .focus, status: .running, remainingSeconds: 59)
        ))
    }
}

// fail 终止壳层行为测试并输出可定位的失败原因。
func fail(_ message: String) -> Never {
    fputs("ShellState test failed: \(message)\n", stderr)
    exit(1)
}

// waitUntil 等待主线程上的异步壳层行为变为可观察状态。
@MainActor
func waitUntil(_ message: String, condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 {
        if condition() {
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    fail(message)
}

// 后端初始提供 15 分钟 idle 快照和 80% 用量时，ShellState 启动后应完整加载快照、按顺序发送六种用户意图、去重重复 hover，并在停止时释放后端。
@MainActor
func testShellStateLoadsBackendAndMapsUserIntents() async {
    let initial = SurfaceState(
        pomodoro: PomodoroSnapshot(mode: .focus, status: .idle, remainingSeconds: 900, focusDurationSeconds: 900),
        codex: CodexUsageSnapshot(
            status: .available,
            primary: CodexUsageWindow(remainingPercent: 80, windowDurationMinutes: 300)
        )
    )
    let backend = FakeBackend(state: initial)
    let state = ShellState(backend: backend)
    state.start()
    await waitUntil("start should load the backend snapshot") {
        state.backendMessage == "Connected" && state.surfaceState == initial
    }

    // 依次触发界面暴露的六种操作时，fake 后端收到的类型和可选时长应与 Go HTTP 合约逐项一致。
    let expected: [(ProductIntent, () -> Void)] = [
        (.pomodoro(.startFocus(durationSeconds: 900)), { state.startFocus(durationSeconds: 900) }),
        (.pomodoro(.pause), { state.pausePomodoro() }),
        (.pomodoro(.resume), { state.resumePomodoro() }),
        (.pomodoro(.reset), { state.resetPomodoro() }),
        (.pomodoro(.startBreak), { state.startBreak() }),
        (.pomodoro(.skipBreak), { state.skipBreak() })
    ]
    for (index, item) in expected.enumerated() {
        item.1()
        await waitUntil("intent \(item.0) should reach the backend") {
            backend.recordedIntents().count == index + 1
        }
        let recorded = backend.recordedIntents()[index]
        if recorded != item.0 {
            fail("intent \(index) = \(recorded), want \(item.0)")
        }
    }

    // 指针连续进入两次再退出时，展开回调应只产生一次 true 和一次 false，不能因重复 hover 重复调整面板。
    var expansionChanges: [Bool] = []
    state.expansionDidChange = { expansionChanges.append($0) }
    state.pointerEntered()
    state.pointerEntered()
    state.pointerExited()
    if expansionChanges != [true, false] {
        fail("hover transitions = \(expansionChanges), want [true, false]")
    }

    // 壳层显式停止时，应同步调用后端 stop，避免遗留 Go 子进程或刷新任务。
    state.stop()
    if !backend.wasStopped() {
        fail("stop should release the backend process")
    }
}

// Todo 页面依次新增、改名、完成和删除时，ShellState 应发送四种独立类型化意图，并只接受 fake 返回的后端快照作为正式列表。
@MainActor
func testShellStateMapsTodoIntentsAndKeepsBackendAuthoritative() async {
    let backendSnapshot = SurfaceState(
        revision: 8,
        todo: TodoSnapshot(items: [TodoItem(id: "server-1", title: "后端事实", status: .open)])
    )
    let backend = FakeBackend(state: backendSnapshot)
    let state = ShellState(backend: backend)

    let created = await state.createTodo(title: "本地草稿")
    let renamed = await state.renameTodo(id: "server-1", title: "新标题")
    let completed = await state.setTodoCompletion(id: "server-1", completed: true)
    let deleted = await state.deleteTodo(id: "server-1")

    if !created || !renamed || !completed || !deleted {
        fail("successful Todo calls should report success")
    }
    let expected: [ProductIntent] = [
        .todo(.create(title: "本地草稿")),
        .todo(.rename(id: "server-1", title: "新标题")),
        .todo(.setCompletion(id: "server-1", completed: true)),
        .todo(.delete(id: "server-1"))
    ]
    if backend.recordedIntents() != expected {
        fail("Todo intents = \(backend.recordedIntents()), want \(expected)")
    }
    if state.surfaceState.todo != backendSnapshot.todo {
        fail("Swift must render the backend Todo snapshot instead of mutating a local list")
    }
}

// 指针离开已展开面板但文本编辑仍活跃时，面板应保持展开；编辑结束且指针仍在外部后才折叠。
@MainActor
func testShellStateKeepsPanelExpandedDuringEditing() {
    let state = ShellState(backend: FakeBackend())
    state.pointerEntered()
    state.setPanelInteractionActive(true)
    state.pointerExited()
    if !state.isExpanded {
        fail("active text editing should hold the expanded panel after pointer exit")
    }
    state.setPanelInteractionActive(false)
    if state.isExpanded {
        fail("ending interaction outside the panel should release expansion")
    }
}

// Todo 编辑期间从待办切到专注时，壳层应只释放编辑锁而保持面板展开，随后指针真正离开才正常折叠。
@MainActor
func testShellStateReleasesEditingForPageSwitchWithoutCollapsing() {
    let state = ShellState(backend: FakeBackend())
    state.pointerEntered()
    state.setPanelInteractionActive(true)

    state.cancelPanelInteraction()
    if !state.isExpanded {
        fail("switching pages should not collapse the expanded panel")
    }

    state.pointerExited()
    if state.isExpanded {
        fail("the panel should collapse after the pointer actually leaves")
    }
}

// 后端分别在启动阶段和已连接后的意图阶段抛错时，ShellState 都应把用户可见连接文案切换为“Backend unavailable”，并且仍可安全停止。
@MainActor
func testShellStateReportsBackendFailures() async {
    let startFailure = FakeBackend()
    startFailure.failsToStart = true
    let unavailableState = ShellState(backend: startFailure)
    unavailableState.start()
    await waitUntil("start failure should be visible") {
        unavailableState.backendMessage == "Backend unavailable"
    }
    unavailableState.stop()

    // 后端先成功连接、随后只让意图调用失败时，失败不能被初始 Connected 状态掩盖。
    let intentFailure = FakeBackend()
    intentFailure.failsIntents = true
    let connectedState = ShellState(backend: intentFailure)
    connectedState.start()
    await waitUntil("healthy backend should connect before testing an intent failure") {
        connectedState.backendMessage == "Connected"
    }
    connectedState.resetPomodoro()
    await waitUntil("intent failure should be visible") {
        connectedState.backendMessage == "Backend unavailable"
    }
    connectedState.stop()
}

// 已连接后只有 Todo 保存请求失败时，ShellState 应报告 Todo 操作错误但保持全局后端为 Connected，避免把局部持久化故障误报成整套服务离线。
@MainActor
func testTodoFailureDoesNotMisreportTheWholeBackendAsOffline() async {
    let backend = FakeBackend()
    let state = ShellState(backend: backend)
    state.start()
    await waitUntil("backend should connect before the Todo-only failure") {
        state.backendMessage == "Connected"
    }
    backend.failsIntents = true

    if await state.createTodo(title: "保留的草稿") {
        fail("failed Todo save should report false")
    }
    if state.backendMessage != "Connected" || state.todoErrorMessage == nil {
        fail("Todo-only failure should keep Connected and expose a Todo error")
    }
    state.stop()
}

// revision 3 的 pause 响应先生效、revision 2 的 running 轮询后到时，ShellState 应保持 paused 而不被旧状态回退。
@MainActor
func testShellStateRejectsOutOfOrderSnapshots() async {
    let backend = OutOfOrderBackend()
    let state = ShellState(backend: backend)
    state.start()
    await waitUntil("initial revision should load before the stale poll begins") {
        state.surfaceState.revision == 1
    }
    await waitUntil("the older polling response should be pending") {
        backend.hasPendingStaleResponse()
    }

    state.pausePomodoro()
    await waitUntil("the newer pause response should become visible") {
        state.surfaceState.revision == 3 && state.surfaceState.pomodoro.status == .paused
    }
    backend.releaseStaleResponse()
    try? await Task.sleep(nanoseconds: 50_000_000)
    if state.surfaceState.revision != 3 || state.surfaceState.pomodoro.status != .paused {
        fail("late revision 2 must not replace paused revision 3")
    }
    state.stop()
}

Task { @MainActor in
    await testShellStateLoadsBackendAndMapsUserIntents()
    await testShellStateReportsBackendFailures()
    await testTodoFailureDoesNotMisreportTheWholeBackendAsOffline()
    await testShellStateRejectsOutOfOrderSnapshots()
    await testShellStateMapsTodoIntentsAndKeepsBackendAuthoritative()
    testShellStateKeepsPanelExpandedDuringEditing()
    testShellStateReleasesEditingForPageSwitchWithoutCollapsing()
    print("Junimo ShellState behavior tests passed")
    exit(0)
}
RunLoop.main.run()
