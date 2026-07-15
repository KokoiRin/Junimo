import Foundation
@testable import JunimoCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Test failed: \(message)\n", stderr)
        exit(1)
    }
}

// expectThrows 执行一个应当失败的协议解码动作，并在意外成功时终止测试进程。
func expectThrows(_ message: String, _ operation: () throws -> Void) {
    do {
        try operation()
        fputs("Test failed: \(message)\n", stderr)
        exit(1)
    } catch {}
}

// 后端返回带额外时长字段、但没有 Codex 节点的 focus/idle 快照时，Swift 应解码核心番茄钟字段、忽略多余字段，并把 codex 保持为 nil。
let idleJSON = """
{
  "revision": 1,
  "pomodoro": {
    "mode": "focus",
    "status": "idle",
    "durationSeconds": 1500,
    "remainingSeconds": 1500,
    "focusDurationSeconds": 1500,
    "breakDurationSeconds": 300
  }
}
"""

let state = try JSONDecoder().decode(SurfaceState.self, from: Data(idleJSON.utf8))
expect(state.pomodoro.mode == .focus, "Swift DTO should decode backend focus mode")
expect(state.pomodoro.status == .idle, "Swift DTO should decode backend idle status")
expect(state.pomodoro.remainingSeconds == 1500, "Swift DTO should decode backend remaining time")
expect(state.codex == nil, "Swift DTO should allow backend snapshots without Codex usage")

// 后端返回带未来未知字段的 break/completed 快照时，Swift 应把 break 映射为 rest、保留 completed 和 45 分钟专注配置，同时忽略未知字段。
let completedBreakJSON = """
{
  "revision": 2,
  "pomodoro": {
    "mode": "break",
    "status": "completed",
    "remainingSeconds": 0,
    "focusDurationSeconds": 2700,
    "completionEvent": {"id": 2, "mode": "break"},
    "futureBackendField": "ignored"
  }
}
"""
let completedBreak = try JSONDecoder().decode(SurfaceState.self, from: Data(completedBreakJSON.utf8))
expect(completedBreak.pomodoro.mode == .rest, "Swift DTO should map the backend break mode to rest")
expect(completedBreak.pomodoro.status == .completed, "Swift DTO should decode completed break snapshots")
expect(completedBreak.pomodoro.focusDurationSeconds == 2700, "Swift DTO should preserve the configured focus duration")
expect(completedBreak.pomodoro.completionEvent?.id == 2, "Swift DTO should preserve the Go-owned completion event id")
expect(completedBreak.pomodoro.completionEvent?.mode == .rest, "Swift DTO should map a Go break completion event to rest")

// 后端返回 Swift 尚未支持的 Pomodoro 状态字符串时，解码应明确失败，不能擅自映射成任意现有 UI 状态。
let invalidStatusJSON = idleJSON.replacingOccurrences(of: "\"idle\"", with: "\"unknown\"")
expectThrows("Unknown backend Pomodoro states should fail decoding instead of inventing UI behavior") {
    _ = try JSONDecoder().decode(SurfaceState.self, from: Data(invalidStatusJSON.utf8))
}

// 后端同时返回 5 小时主窗口和 7 天次窗口时，折叠胶囊应只展示产品约定的主窗口短文案“5h 94%”。
let codexJSON = """
{
  "revision": 3,
  "pomodoro": {
    "mode": "focus",
    "status": "idle",
    "durationSeconds": 1500,
    "remainingSeconds": 1500,
    "focusDurationSeconds": 1500,
    "breakDurationSeconds": 300
  },
  "codex": {
    "status": "available",
    "primary": {"remainingPercent": 94, "windowDurationMinutes": 300, "resetsAt": 1783655023},
    "secondary": {"remainingPercent": 99, "windowDurationMinutes": 10080, "resetsAt": 1784241823}
  }
}
"""

let stateWithCodex = try JSONDecoder().decode(SurfaceState.self, from: Data(codexJSON.utf8))
expect(stateWithCodex.codex?.compactSummary == "5h 94%", "Collapsed quota should omit the Codex label and show the primary five-hour window")

// 后端返回一条未完成和一条已完成 Todo 时，Swift 应保留稳定 ID、顺序与状态；旧快照缺少 Todo 节点时则降级为空列表。
let todoJSON = """
{
  "revision": 4,
  "pomodoro": {
    "mode": "focus",
    "status": "idle",
    "remainingSeconds": 1500,
    "focusDurationSeconds": 1500
  },
  "todo": {
    "status": "available",
    "items": [
      {"id": "todo-2", "title": "实现页面", "status": "open"},
      {"id": "todo-1", "title": "完成设计", "status": "completed"}
    ]
  }
}
"""
let stateWithTodo = try JSONDecoder().decode(SurfaceState.self, from: Data(todoJSON.utf8))
expect(stateWithTodo.todo.items.map(\.id) == ["todo-2", "todo-1"], "Todo decoding should preserve backend order and stable IDs")
expect(stateWithTodo.todo.items.map(\.status) == [.open, .completed], "Todo decoding should preserve explicit completion states")
expect(state.todo == TodoSnapshot(), "Snapshots without Todo should decode as an empty loading-safe Todo snapshot")

// 四种类型化 Todo 意图编码后应分别只携带 Go 合约规定的 title、id 或 completed 字段，不能泄露其他动作参数。
let todoRequests: [(ProductIntent, String)] = [
    (.todo(.create(title: "写测试")), #"{"title":"写测试","type":"todo.create"}"#),
    (.todo(.rename(id: "1", title: "改标题")), #"{"id":"1","title":"改标题","type":"todo.rename"}"#),
    (.todo(.setCompletion(id: "1", completed: true)), #"{"completed":true,"id":"1","type":"todo.setCompletion"}"#),
    (.todo(.delete(id: "1")), #"{"id":"1","type":"todo.delete"}"#)
]
for (intent, expectedJSON) in todoRequests {
    let encoded = try JSONEncoder().encode(BackendIntentRequest(intent: intent))
    let object = try JSONSerialization.jsonObject(with: encoded) as! NSDictionary
    let expected = try JSONSerialization.jsonObject(with: Data(expectedJSON.utf8)) as! NSDictionary
    expect(object == expected, "Typed Todo request \(intent) should encode its unique Go wire shape")
}

// 用量分别处于 loading、unavailable 和 available 但缺少主窗口时，短文案应稳定降级为省略号或破折号，不能伪造百分比。
expect(CodexUsageSnapshot(status: .loading).compactSummary == "…", "Loading quota should stay compact and not invent a number")
expect(CodexUsageSnapshot(status: .unavailable).compactSummary == "—", "Unavailable quota should degrade explicitly without widening the capsule")
expect(CodexUsageSnapshot(status: .available).compactSummary == "—", "Available quota without a primary window should degrade explicitly")

// 主窗口分别为 45 分钟 75%、5 小时 101% 和 7 天 -1% 时，文案应选择分钟/小时/天单位，并把百分比限制在 0...100。
expect(
    CodexUsageSnapshot(status: .available, primary: CodexUsageWindow(remainingPercent: 75, windowDurationMinutes: 45)).compactSummary == "45m 75%",
    "Sub-hour quota windows should stay in minutes"
)
expect(
    CodexUsageSnapshot(status: .available, primary: CodexUsageWindow(remainingPercent: 101, windowDurationMinutes: 300)).compactSummary == "5h 100%",
    "Displayed quota should clamp percentages above 100"
)
expect(
    CodexUsageSnapshot(status: .available, primary: CodexUsageWindow(remainingPercent: -1, windowDurationMinutes: 10080)).compactSummary == "7d 0%",
    "Displayed quota should clamp negative percentages and format whole days"
)

// 菜单栏 inset 分别为正常 33、隐藏 0、异常负值和较大 60 时，折叠面板应采用真实正高度，并始终保持至少 28pt。
expect(
    NotchPanelMetrics.collapsedHeight(screenTop: 1000, visibleTop: 967) == 33,
    "Collapsed notch should fill the menu bar height"
)
expect(
    NotchPanelMetrics.collapsedHeight(screenTop: 1000, visibleTop: 1000) == 28,
    "Collapsed notch should keep its minimum height when the menu bar inset is hidden"
)
expect(
    NotchPanelMetrics.collapsedHeight(screenTop: 1000, visibleTop: 1010) == 28,
    "Collapsed notch should reject negative menu bar insets"
)
expect(
    NotchPanelMetrics.collapsedHeight(screenTop: 1000, visibleTop: 940) == 60,
    "Collapsed notch should preserve a larger real menu bar inset"
)

// 应用首次连接时若 Go 已经有 id 5 的完成事件，通知门禁应只建立基线，不补发用户可能早已看过的旧提醒。
var completionGate = PomodoroCompletionNotificationGate()
let initialCompletion = completionGate.observe(PomodoroCompletionEvent(id: 5, mode: .focus))
expect(initialCompletion == nil, "Connecting to an existing completion event should only establish a baseline")

// 首快照没有完成事件、后续出现 id 1 的 focus 事件时应提醒一次，重复 id 1 不得再次提醒。
completionGate = PomodoroCompletionNotificationGate()
_ = completionGate.observe(nil)
let focusEvent = PomodoroCompletionEvent(id: 1, mode: .focus)
expect(completionGate.observe(focusEvent) == .focus, "A new Go-owned focus event should notify")
expect(completionGate.observe(focusEvent) == nil, "The same completion event id should not notify twice")

// 已投递 id 2 的 rest 事件后，晚到的 id 1 不得被当作新完成，更大的 id 3 仍应正常投递。
completionGate = PomodoroCompletionNotificationGate()
_ = completionGate.observe(nil)
expect(completionGate.observe(PomodoroCompletionEvent(id: 2, mode: .rest)) == .rest, "A new rest event should notify")
expect(completionGate.observe(PomodoroCompletionEvent(id: 1, mode: .focus)) == nil, "An older event id should be ignored")
expect(completionGate.observe(PomodoroCompletionEvent(id: 3, mode: .focus)) == .focus, "A later event id should still notify")

print("JunimoCore shell DTO smoke tests passed")
