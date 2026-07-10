import Foundation

public protocol ShellBackendClient: AnyObject {
    func start() async throws
    func stop()
    func loadState() async throws -> SurfaceState
    func sendIntent(_ intent: BackendIntent) async throws -> SurfaceState
}

public final class GoBackendClient: ShellBackendClient {
    private struct HealthResponse: Decodable {
        var status: String
        var protocolVersion: Int
    }

    private static let supportedProtocolVersion = 2

    private let port: Int
    private var process: Process?

    public init(port: Int = 44832) {
        self.port = port
    }

    public func start() async throws {
        if try await isHealthy() {
            return
        }
        guard process == nil else {
            try await waitUntilHealthy()
            return
        }
        guard let executableURL = backendExecutableURL() else {
            throw BackendError.executableNotFound
        }

        let process = Process()
        process.executableURL = executableURL
        process.environment = ProcessInfo.processInfo.environment.merging([
            "JUNIMO_BACKEND_PORT": "\(port)"
        ]) { _, new in new }
        self.process = process
        try process.run()
        try await waitUntilHealthy()
    }

    public func stop() {
        process?.terminate()
        process = nil
    }

    public func loadState() async throws -> SurfaceState {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("state"))
        try validate(response)
        return try JSONDecoder().decode(SurfaceState.self, from: data)
    }

    public func sendIntent(_ intent: BackendIntent) async throws -> SurfaceState {
        var request = URLRequest(url: baseURL.appendingPathComponent("intent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(intent)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(SurfaceState.self, from: data)
    }

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    private func isHealthy() async throws -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("health"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return false
            }
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            return health.status == "ok" && health.protocolVersion == Self.supportedProtocolVersion
        } catch {
            return false
        }
    }

    private func waitUntilHealthy() async throws {
        for _ in 0..<30 {
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
}
