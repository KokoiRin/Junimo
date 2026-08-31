import Combine
import Darwin
import Dispatch
import Foundation

// QuickLaunchConfigurationStore 封装外部 JSON 的创建、校验、最后正确值与目录级热更新。
@MainActor
public final class QuickLaunchConfigurationStore: ObservableObject {
    @Published public private(set) var commands: [QuickLaunchCommand]
    @Published public private(set) var lastErrorDescription: String?

    public let fileURL: URL

    private let defaultConfiguration: QuickLaunchConfiguration
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var reloadTask: Task<Void, Never>?
    private var started = false

    public init(
        fileURL: URL = QuickLaunchConfigurationStore.defaultFileURL(),
        defaultConfiguration: QuickLaunchConfiguration = QuickLaunchCatalog.defaultConfiguration
    ) {
        self.fileURL = fileURL
        self.defaultConfiguration = defaultConfiguration
        commands = (try? QuickLaunchCatalog.commands(from: defaultConfiguration)) ?? QuickLaunchCatalog.commands
    }

    public nonisolated static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return applicationSupport
            .appendingPathComponent("Junimo", isDirectory: true)
            .appendingPathComponent("quick-launch.json", isDirectory: false)
    }

    public func start() {
        guard !started else { return }
        started = true
        reloadFromDisk()
        beginWatchingDirectory()
    }

    public func stop() {
        started = false
        reloadTask?.cancel()
        reloadTask = nil
        fileWatcher?.cancel()
        fileWatcher = nil
        directoryWatcher?.cancel()
        directoryWatcher = nil
    }

    public func reloadFromDisk() {
        defer {
            if started {
                restartFileWatcher()
            }
        }
        do {
            try ensureConfigurationFileExists()
            let data = try Data(contentsOf: fileURL)
            commands = try QuickLaunchCatalog.decode(data)
            lastErrorDescription = nil
        } catch {
            // 配置暂时写坏或原子替换尚未完成时保留最后一次正确目录。
            lastErrorDescription = error.localizedDescription
        }
    }

    private func ensureConfigurationFileExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try QuickLaunchCatalog.encode(defaultConfiguration).write(to: fileURL, options: .atomic)
    }

    private func beginWatchingDirectory() {
        let directoryURL = fileURL.deletingLastPathComponent()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            lastErrorDescription = "无法监听快捷入口配置目录"
            return
        }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        watcher.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        watcher.setCancelHandler {
            close(descriptor)
        }
        directoryWatcher = watcher
        watcher.resume()
    }

    private func restartFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil

        let descriptor = open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            if lastErrorDescription == nil {
                lastErrorDescription = "无法监听快捷入口配置文件"
            }
            return
        }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )
        watcher.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        watcher.setCancelHandler {
            close(descriptor)
        }
        fileWatcher = watcher
        watcher.resume()
    }

    private func scheduleReload() {
        guard started else { return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.reloadFromDisk()
        }
    }
}
