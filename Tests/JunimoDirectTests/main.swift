import Foundation
@testable import JunimoCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Test failed: \(message)\n", stderr)
        exit(1)
    }
}

// v5 后端快照应完整解码用量、activity 和稳定完成事件。
let stateJSON = """
{
  "revision": 7,
  "codex": {
    "status": "available",
    "primary": {"remainingPercent": 82, "windowDurationMinutes": 300, "resetsAt": 1783655023}
  },
  "activity": {
    "status": "available",
    "completionEvent": {
      "id": "turn-1",
      "threadId": "thread-1",
      "title": "实现轻量 Junimo",
      "completedAt": 1783655000
    }
  }
}
"""
let state = try JSONDecoder().decode(SurfaceState.self, from: Data(stateJSON.utf8))
expect(state.revision == 7, "State should preserve backend revision")
expect(state.codex.compactSummary == "5h 82%", "State should format the primary Codex window")
expect(state.activity.status == .available, "State should preserve activity availability")
expect(state.activity.completionEvent?.id == "turn-1", "State should preserve stable turn identity")
expect(state.activity.completionEvent?.title == "实现轻量 Junimo", "State should preserve the task title")

// 用量 loading、unavailable 与异常百分比应稳定降级，不得制造看似可信的额度。
expect(CodexUsageSnapshot(status: .loading).compactSummary == "…", "Loading usage should stay compact")
expect(CodexUsageSnapshot(status: .unavailable).compactSummary == "—", "Unavailable usage should be explicit")
expect(
    CodexUsageSnapshot(
        status: .available,
        primary: CodexUsageWindow(remainingPercent: 101, windowDurationMinutes: 300)
    ).compactSummary == "5h 100%",
    "Usage display should clamp invalid percentages"
)

// Go 已建立历史基线后，Swift 收到的第一条完成事件必须立即提醒，重复快照不得再次提醒。
var gate = CodexCompletionNotificationGate()
let fresh = CodexCompletionEvent(id: "turn-new", threadId: "thread-new", title: "新任务", completedAt: 2)
expect(gate.observe(fresh) == fresh, "The first backend completion event should notify")
expect(gate.observe(fresh) == nil, "The same turn should not notify twice")

// 空轮询不应改变通知门状态，后续不同 turn 仍应各自投递一次。
expect(gate.observe(nil) == nil, "An empty poll should not notify")
let next = CodexCompletionEvent(id: "turn-next", threadId: "thread-next", title: "下一个任务", completedAt: 3)
expect(gate.observe(next) == next, "A different stable turn should notify")

// 完成通知中的有效 Codex 任务 ID 应生成对应任务深链接，无效 ID 则交给应用级回退处理。
let codexThreadID = "019d1f61-0dd7-7dd1-b6f4-0d64c4c162a1"
expect(
    CodexTaskLink.url(threadID: codexThreadID)?.absoluteString == "codex://threads/\(codexThreadID)",
    "A Codex thread should preserve its identity in the deep link"
)
expect(CodexTaskLink.url(threadID: "thread-new") == nil, "An invalid thread ID should not create a broken deep link")
expect(CodexTaskLink.bundleIdentifier == "com.openai.codex", "The fallback should target the Codex application")

final class FakeWorkspace: QuickLaunchOpening {
    var applicationBundleIdentifiers: [String] = []
    var URLs: [URL] = []

    func openApplication(bundleIdentifier: String) -> Bool {
        applicationBundleIdentifiers.append(bundleIdentifier)
        return true
    }

    func openURL(_ url: URL) -> Bool {
        URLs.append(url)
        return true
    }
}

// 默认目录只应包含应用类 Codex 和网页类 RIN，并通过各自的 workspace 动作执行。
let workspace = FakeWorkspace()
let launcher = QuickLauncher(workspace: workspace)
let sections = QuickLaunchCatalog.sections
expect(sections.map(\.category) == [.application, .website], "Catalog should group applications before websites")
expect(sections.flatMap(\.commands).map(\.id) == ["codex", "rin"], "Catalog should expose only Codex and RIN")

let codexCommand = QuickLaunchCatalog.commands.first { $0.id == "codex" }!
let rinCommand = QuickLaunchCatalog.commands.first { $0.id == "rin" }!
expect(launcher.open(codexCommand), "Codex shortcut should open")
expect(launcher.open(rinCommand), "RIN shortcut should open")
expect(workspace.applicationBundleIdentifiers == ["com.openai.codex"], "Codex should route by bundle identifier")
expect(
    workspace.URLs == [URL(string: "https://kokoirin.github.io/rin3/")!],
    "RIN should preserve its fixed HTTPS destination"
)

// 菜单栏 inset 为正常值或隐藏值时，折叠高度应跟随真实高度并保留 28pt 下限。
expect(NotchPanelMetrics.collapsedHeight(screenTop: 1000, visibleTop: 967) == 33, "Panel should follow the menu bar")
expect(NotchPanelMetrics.collapsedHeight(screenTop: 1000, visibleTop: 1000) == 28, "Panel should keep its minimum height")

print("JunimoCore companion tests passed")
