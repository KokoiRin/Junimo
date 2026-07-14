import Darwin
import Foundation
import JunimoCore

// fail 终止真实 Swift-Go 契约测试并输出可定位原因。
func fail(_ message: String) -> Never {
    fputs("Backend contract test failed: \(message)\n", stderr)
    exit(1)
}

// ContractTestError 把契约断言失败送入统一 cleanup 路径，避免直接退出遗留 Go 子进程。
enum ContractTestError: Error {
    case failed(String)
}

// expect 要求跨进程可观察行为成立，不检查 adapter 内部实现。
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw ContractTestError.failed(message)
    }
}

guard CommandLine.arguments.count == 2 else {
    fail("expected the junimo-backend executable path")
}
setenv("JUNIMO_BACKEND_EXECUTABLE", CommandLine.arguments[1], 1)

Task {
    // 真实 Swift client 向新启动的 Go backend 发送类型化 startFocus 与 pause 时，应得到严格递增 revision 的 running 和 paused 快照。
    let port = 46_000 + Int(getpid() % 1_000)
    let backend = GoBackendClient(port: port)
    do {
        try await backend.start()
        let initial = try await backend.loadState()
        let running = try await backend.sendIntent(.startFocus(durationSeconds: 60))
        let paused = try await backend.sendIntent(.pause)

        try expect(initial.revision > 0, "initial state should carry a positive revision")
        try expect(running.revision > initial.revision, "startFocus should return a newer revision")
        try expect(running.pomodoro.status == .running, "typed startFocus should reach the Go state machine")
        try expect(running.pomodoro.focusDurationSeconds == 60, "startFocus should preserve its associated duration")
        try expect(paused.revision > running.revision, "pause should return a newer revision")
        try expect(paused.pomodoro.status == .paused, "typed pause should reach the Go state machine")
        backend.stop()
        print("Junimo Swift-Go backend contract tests passed")
        exit(0)
    } catch {
        backend.stop()
        fail(String(describing: error))
    }
}

RunLoop.main.run()
