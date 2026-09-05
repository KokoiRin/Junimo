import Darwin
import Foundation
import JunimoCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Junimo instance test failed: \(message)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "hold" {
    let lock = AppInstanceLock(fileURL: URL(fileURLWithPath: CommandLine.arguments[2]))
    guard try lock.acquire() else { exit(2) }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    try child.run()
    try "\(getpid()) \(child.processIdentifier)".write(toFile: CommandLine.arguments[3], atomically: true, encoding: .utf8)
    withExtendedLifetime(lock) { _ = sleep(30) }
    child.terminate()
    child.waitUntilExit()
    exit(0)
}

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("junimo-instance-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let lockURL = directory.appendingPathComponent("shell.lock")
let readyURL = directory.appendingPathComponent("ready")

// 同一把锁首次获取成功，另一个持有者被拒绝；主动释放后，已有锁文件不妨碍再次启动。
let first = AppInstanceLock(fileURL: lockURL)
let second = AppInstanceLock(fileURL: lockURL)
let acquired = try first.acquire()
expect(acquired, "first owner should acquire the lock")
let duplicate = try second.acquire()
expect(!duplicate, "a second owner should be rejected")
first.release()
let reacquired = try second.acquire()
expect(reacquired, "released lock should be reusable")
second.release()

// 八个独立进程同时竞争同一路径时只能留下一个持有者，其余进程应识别到已有实例并退出。
var contenders: [Process] = []
defer {
    for process in contenders where process.isRunning {
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }
}
for _ in 0..<8 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["hold", lockURL.path, readyURL.path]
    try process.run()
    contenders.append(process)
}
for _ in 0..<100 {
    if FileManager.default.fileExists(atPath: readyURL.path), contenders.filter({ $0.isRunning }).count == 1 { break }
    usleep(50_000)
}
let running = contenders.filter { $0.isRunning }
expect(running.count == 1, "exactly one process should remain")
for process in contenders where !process.isRunning {
    expect(process.terminationStatus == 2, "other processes should report an existing owner")
}
let pids = try String(contentsOf: readyURL, encoding: .utf8).split(separator: " ").compactMap { Int32($0) }
expect(pids.count == 2, "owner and its child should be ready")
defer { kill(pids[1], SIGTERM) }

// 持有者被强制结束后，即使它启动的子进程仍然存活，新实例也能立即获取锁，不需要清理残留文件。
kill(running[0].processIdentifier, SIGKILL)
running[0].waitUntilExit()
expect(kill(pids[1], 0) == 0, "child should still be running for the inheritance check")
let afterCrash = try first.acquire()
expect(afterCrash, "crash must release the lock without leaking it to a child")
first.release()
print("Junimo single-instance process tests passed")
