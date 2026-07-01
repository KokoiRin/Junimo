import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum BrokenPipeGuard {
    private static let installOnce: Void = {
        #if canImport(Darwin)
        signal(SIGPIPE, SIG_IGN)
        #endif
    }()

    public static func install() {
        _ = installOnce
    }

    static func write(_ data: Data, to handle: FileHandle) -> Bool {
        install()
        #if canImport(Darwin)
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return true
            }
            var bytesWritten = 0
            while bytesWritten < data.count {
                let result = Darwin.write(
                    handle.fileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    data.count - bytesWritten
                )
                if result > 0 {
                    bytesWritten += result
                    continue
                }
                if result == -1 && errno == EINTR {
                    continue
                }
                return false
            }
            return true
        }
        #else
        handle.write(data)
        return true
        #endif
    }
}
