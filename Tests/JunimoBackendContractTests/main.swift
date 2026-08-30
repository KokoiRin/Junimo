import Darwin
import Foundation
import JunimoCore

func fail(_ message: String) -> Never {
    fputs("Backend contract test failed: \(message)\n", stderr)
    exit(1)
}

enum ContractTestError: Error {
    case failed(String)
}

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
    // 真实 Swift client 启动 Go 后端后，应连续解码 v5 只读快照并观察到单调 revision。
    let port = 46_000 + Int(getpid() % 1_000)
    let backend = GoBackendClient(port: port)
    do {
        try await backend.start()
        let first = try await backend.loadState()
        let second = try await backend.loadState()

        try expect(first.revision > 0, "initial state should carry a positive revision")
        try expect(second.revision > first.revision, "later state should carry a newer revision")
        try expect(
            [.loading, .available, .unavailable].contains(first.codex.status),
            "Codex usage should decode a declared availability state"
        )
        try expect(
            [.loading, .available, .unavailable].contains(first.activity.status),
            "Codex activity should decode independently from usage"
        )

        backend.stop()
        print("Junimo Swift-Go v5 contract tests passed")
        exit(0)
    } catch {
        backend.stop()
        fail(String(describing: error))
    }
}

RunLoop.main.run()
