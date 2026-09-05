import Darwin
import Foundation

// 锁属于当前用户，不随 App 所在目录变化；内核会在进程退出时释放它。
public final class AppInstanceLock {
    private let fileURL: URL
    private var descriptor: Int32 = -1

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func acquire() throws -> Bool {
        if descriptor >= 0 { return true }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let candidate = Darwin.open(fileURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard candidate >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(candidate, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            Darwin.close(candidate)
            if error == EWOULDBLOCK { return false }
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }
        descriptor = candidate
        return true
    }

    public func release() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
        // 不删除文件：删除后重新创建会产生另一个 inode，让两个进程各持一把锁。
    }

    deinit { release() }
}
