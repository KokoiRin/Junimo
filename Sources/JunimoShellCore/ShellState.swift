import Combine
import Foundation

@MainActor
public final class ShellState: ObservableObject {
    @Published public private(set) var isExpanded = false
    @Published public private(set) var surfaceState = SurfaceState()
    @Published public private(set) var backendMessage = "Starting"
    @Published public private(set) var todoErrorMessage: String?

    public var expansionDidChange: ((Bool) -> Void)?

    private let backend: ShellBackendClient
    private var refreshTask: Task<Void, Never>?
    private var pointerIsInside = false
    private var panelInteractionIsActive = false
    // latestRevision 记录已渲染的最新 Go 快照序号，使轮询与意图响应可以安全乱序到达。
    private var latestRevision: UInt64?

    public init(backend: ShellBackendClient = GoBackendClient()) {
        self.backend = backend
    }

    deinit {
        refreshTask?.cancel()
        backend.stop()
    }

    public func start() {
        refreshTask?.cancel()
        latestRevision = nil
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await backend.start()
                backendMessage = "Connected"
                accept(try await backend.loadState())
                await pollBackend()
            } catch {
                backendMessage = "Backend unavailable"
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        backend.stop()
    }

    public func pointerEntered() {
        pointerIsInside = true
        setExpanded(true)
    }

    public func pointerExited() {
        pointerIsInside = false
        if !panelInteractionIsActive {
            setExpanded(false)
        }
    }

    // setPanelInteractionActive 在文本焦点等直接交互期间持有展开状态，交互结束后按真实指针位置释放。
    public func setPanelInteractionActive(_ active: Bool) {
        panelInteractionIsActive = active
        if active {
            setExpanded(true)
        } else if !pointerIsInside {
            setExpanded(false)
        }
    }

    // cancelPanelInteraction 用于页面切换时只释放编辑锁，避免导航动作被误解释为离开面板。
    public func cancelPanelInteraction() {
        panelInteractionIsActive = false
    }

    public func startFocus(durationSeconds: Int = 25 * 60) {
        Task {
            await applyIntent(.pomodoro(.startFocus(durationSeconds: durationSeconds)))
        }
    }

    public func pausePomodoro() {
        Task {
            await applyIntent(.pomodoro(.pause))
        }
    }

    public func resumePomodoro() {
        Task {
            await applyIntent(.pomodoro(.resume))
        }
    }

    public func resetPomodoro() {
        Task {
            await applyIntent(.pomodoro(.reset))
        }
    }

    public func startBreak() {
        Task {
            await applyIntent(.pomodoro(.startBreak))
        }
    }

    public func skipBreak() {
        Task {
            await applyIntent(.pomodoro(.skipBreak))
        }
    }

    // createTodo 把新增草稿作为意图发送，只有后端快照成功返回时才报告成功。
    @discardableResult
    public func createTodo(title: String) async -> Bool {
        await applyIntent(.todo(.create(title: title)))
    }

    // renameTodo 请求 Go 修改指定稳定 ID 的标题，不在 Swift 中预改正式列表。
    @discardableResult
    public func renameTodo(id: String, title: String) async -> Bool {
        await applyIntent(.todo(.rename(id: id, title: title)))
    }

    // setTodoCompletion 请求明确目标完成态，避免重试时反向切换。
    @discardableResult
    public func setTodoCompletion(id: String, completed: Bool) async -> Bool {
        await applyIntent(.todo(.setCompletion(id: id, completed: completed)))
    }

    // deleteTodo 请求 Go 幂等删除稳定 ID 对应的任务。
    @discardableResult
    public func deleteTodo(id: String) async -> Bool {
        await applyIntent(.todo(.delete(id: id)))
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        expansionDidChange?(expanded)
    }

    // applyIntent 统一提交产品动作，并只用成功返回的 Go 快照更新正式界面状态。
    private func applyIntent(_ intent: ProductIntent) async -> Bool {
        do {
            accept(try await backend.sendIntent(intent))
            backendMessage = "Connected"
            if case .todo = intent {
                todoErrorMessage = nil
            }
            return true
        } catch {
            if case .todo = intent {
                todoErrorMessage = "保存待办失败，请稍后重试"
            } else {
                backendMessage = "Backend unavailable"
            }
            return false
        }
    }

    private func pollBackend() async {
        while !Task.isCancelled {
            do {
                accept(try await backend.loadState())
                backendMessage = "Connected"
            } catch {
                backendMessage = "Backend unavailable"
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // accept 只接受首份或 revision 严格更大的 Go 快照，相等与更旧响应均不得覆盖 UI。
    private func accept(_ snapshot: SurfaceState) {
        if let latestRevision, snapshot.revision <= latestRevision {
            return
        }
        latestRevision = snapshot.revision
        surfaceState = snapshot
    }
}
