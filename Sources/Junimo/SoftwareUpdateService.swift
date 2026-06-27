import Foundation
import JunimoCore

protocol ReleaseChecking {
    func checkLatestRelease(completion: @escaping (SelfUpdateCheckResult) -> Void)
}

enum SoftwareUpdateCheckReason {
    case automatic
    case manual
}

final class SoftwareUpdateService {
    private let coordinator: TaskCoordinator
    private let checker: ReleaseChecking
    private let checksOnStart: Bool
    private let nowProvider: () -> Date
    private var isRunning = false
    private var isChecking = false

    /// 业务语义：update service 只调度检查生命周期，版本规则仍由 coordinator/core 维护。
    init(
        coordinator: TaskCoordinator,
        checker: ReleaseChecking,
        checksOnStart: Bool = true,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.checker = checker
        self.checksOnStart = checksOnStart
        self.nowProvider = nowProvider
    }

    /// 业务语义：启动时可低成本检查一次新版本，但不做静默安装。
    func start() {
        isRunning = true
        if checksOnStart {
            checkNow(reason: .automatic)
        }
    }

    /// 业务语义：停止后忽略异步 release 回调，避免退出过程污染 UI 状态。
    func stop() {
        isRunning = false
    }

    /// 业务语义：手动/启动检查共用单飞门禁，避免菜单连点制造交错状态。
    func checkNow(reason: SoftwareUpdateCheckReason) {
        guard isRunning, !isChecking else { return }
        isChecking = true
        coordinator.startSelfUpdateCheck(now: nowProvider())
        checker.checkLatestRelease { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.isChecking = false
                self.coordinator.applySelfUpdateCheck(result, now: self.nowProvider())
            }
        }
    }
}

final class GitHubReleaseChecker: ReleaseChecking {
    private struct GitHubRelease: Decodable {
        var tagName: String
        var assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        var name: String
    }

    private let url: URL
    private let assetName: String
    private let session: URLSession

    /// 业务语义：GitHub checker 只读取 release 元数据，不下载或安装 app bundle。
    init(
        url: URL = URL(string: "https://api.github.com/repos/KokoiRin/Junimo/releases/latest")!,
        assetName: String = "Junimo-macos-arm64.zip",
        session: URLSession = .shared
    ) {
        self.url = url
        self.assetName = assetName
        self.session = session
    }

    /// 业务语义：只有可解析 tag 且存在稳定 release asset 时，检查才算成功。
    func checkLatestRelease(completion: @escaping (SelfUpdateCheckResult) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request) { [assetName] data, response, error in
            if let error {
                completion(.failure(error.localizedDescription))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion(.failure("GitHub release check failed with HTTP \(http.statusCode)"))
                return
            }
            guard let data else {
                completion(.failure("GitHub release response was empty"))
                return
            }
            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard let version = ReleaseVersion(tag: release.tagName) else {
                    completion(.failure("GitHub release tag is not a stable version"))
                    return
                }
                guard release.assets.contains(where: { $0.name == assetName }) else {
                    completion(.failure("GitHub release is missing \(assetName)"))
                    return
                }
                completion(.success(ReleaseInfo(version: version, assetName: assetName)))
            } catch {
                completion(.failure("GitHub release metadata could not be parsed"))
            }
        }
        task.resume()
    }
}

protocol ExternalUpdateInstalling {
    func installLatest(from installDirectory: String) throws
}

final class ExternalUpdateInstaller: ExternalUpdateInstalling {
    private let scriptURL: URL

    init(scriptURL: URL = URL(string: "https://raw.githubusercontent.com/KokoiRin/Junimo/main/scripts/update_latest.sh")!) {
        self.scriptURL = scriptURL
    }

    /// 业务语义：真实安装交给外部 updater，当前 app 只负责传递当前安装目录。
    func installLatest(from installDirectory: String) throws {
        let command = "export JUNIMO_INSTALL_DIR='\(Self.shellEscaped(installDirectory))'; curl -fsSL '\(scriptURL.absoluteString)' | bash"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        try process.run()
    }

    /// 业务语义：安装目录作为 shell 字面量传入 updater，支持路径中包含空格或单引号。
    private static func shellEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }
}
