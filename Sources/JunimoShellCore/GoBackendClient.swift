import Foundation

public protocol ShellBackendClient: AnyObject {
    func start() async throws
    func stop()
    func loadState() async throws -> SurfaceState
}

public final class GoBackendClient: ShellBackendClient {
    private struct HealthResponse: Decodable {
        var status: String
        var protocolVersion: Int
        var instanceId: String?
    }

    private static let supportedProtocolVersion = 5
    private let port: Int
    private var process: Process?
    private var instanceID: String?

    public init(port: Int = 44832) {
        self.port = port
    }

    public func start() async throws {
        guard process == nil else {
            try await waitUntilHealthy()
            return
        }
        guard let executableURL = backendExecutableURL() else {
            throw BackendError.executableNotFound
        }

        let process = Process()
        let instanceID = UUID().uuidString
        process.executableURL = executableURL
        process.environment = ProcessInfo.processInfo.environment.merging([
            "JUNIMO_BACKEND_PORT": "\(port)",
            "JUNIMO_INSTANCE_ID": instanceID
        ]) { _, new in new }
        self.process = process
        self.instanceID = instanceID
        do {
            try process.run()
            try await waitUntilHealthy()
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        instanceID = nil
    }

    public func loadState() async throws -> SurfaceState {
        guard process?.isRunning == true else { throw BackendError.backendExited }
        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("state"))
        try validate(response)
        return try JSONDecoder().decode(SurfaceState.self, from: data)
    }

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    // 协议兼容不代表进程归属一致；只接受本次启动生成的实例标识。
    private func isHealthy() async throws -> Bool {
        guard let instanceID, process?.isRunning == true else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("health"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return false
            }
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            return health.status == "ok" && health.protocolVersion == Self.supportedProtocolVersion
                && health.instanceId == instanceID
        } catch {
            return false
        }
    }

    private func waitUntilHealthy() async throws {
        for _ in 0..<30 {
            guard process?.isRunning == true else { throw BackendError.backendExited }
            if try await isHealthy() {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw BackendError.healthCheckTimedOut
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw BackendError.invalidResponse
        }
        guard let instanceID, http.value(forHTTPHeaderField: "X-Junimo-Instance-ID") == instanceID else {
            throw BackendError.instanceMismatch
        }
    }

    private func backendExecutableURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["JUNIMO_BACKEND_EXECUTABLE"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "junimo-backend") {
            return bundled
        }
        if let executableURL = Bundle.main.executableURL {
            let sibling = executableURL.deletingLastPathComponent().appendingPathComponent("junimo-backend")
            if FileManager.default.isExecutableFile(atPath: sibling.path) {
                return sibling
            }
        }
        let direct = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/direct/junimo-backend")
        return FileManager.default.isExecutableFile(atPath: direct.path) ? direct : nil
    }
}

public enum BackendError: Error, Equatable {
    case executableNotFound
    case healthCheckTimedOut
    case invalidResponse
    case backendExited
    case instanceMismatch
}
