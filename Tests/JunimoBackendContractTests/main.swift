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
    // 真实 Swift client 启动 Go 后端后，应连续解码 v6 只读快照并观察到单调 revision。
    let port = 46_000 + Int(getpid() % 1_000)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("junimo-shortcuts-contract-\(UUID().uuidString)")
    setenv("JUNIMO_DATA_DIR", directory.path, 1)
    defer { try? FileManager.default.removeItem(at: directory) }
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

        // 真实客户端必须读取首次导入的收藏、保存调序结果，并从后端重启后的磁盘恢复同一列表。
        let imported = try await backend.loadAppShortcuts()
        try expect(imported.items.map(\.bundleId) == ["com.openai.codex"], "missing initial app import")
        let saved = [AppShortcut(bundleId: "com.apple.finder", name: "Finder"), AppShortcut(bundleId: "com.openai.codex", name: "Codex")]
        let result = try await backend.saveAppShortcuts(saved, revision: imported.revision)
        try expect(result.items == saved, "saved list should match confirmed backend response")

        // 真实 HTTP 客户端提交旧版本时必须收到冲突，刚保存的收藏和顺序不能被空列表覆盖。
        var rejectedStaleSave = false
        do { _ = try await backend.saveAppShortcuts([], revision: imported.revision) }
        catch AppShortcutError.conflict { rejectedStaleSave = true }
        try expect(rejectedStaleSave, "stale HTTP write should return a typed conflict")
        let afterConflict = try await backend.loadAppShortcuts()
        try expect(afterConflict == result, "conflict must preserve the saved snapshot")

        // 已有同协议后端占用端口时，另一客户端必须启动失败，不能冒用已有后端或关闭它。
        let duplicate = GoBackendClient(port: port)
        var rejectedDuplicate = false
        do {
            try await duplicate.start()
        } catch {
            rejectedDuplicate = true
        }
        duplicate.stop()
        try expect(rejectedDuplicate, "a foreign backend must not satisfy startup")
        let stillOwned = try await backend.loadState()
        try expect(stillOwned.revision > second.revision, "original backend must remain usable")

        // 同一客户端重复 start 应复用自己拥有的后端，停止后重新启动则建立新的实例。
        try await backend.start()
        backend.stop()
        try await backend.start()
        _ = try await backend.loadState()
        let restored = try await backend.loadAppShortcuts()
        try expect(restored.items == saved, "backend restart should preserve app order")

        backend.stop()
        print("Junimo Swift-Go v6 contract tests passed")
        try? FileManager.default.removeItem(at: directory)
        exit(0)
    } catch {
        backend.stop()
        fail(String(describing: error))
    }
}

RunLoop.main.run()
