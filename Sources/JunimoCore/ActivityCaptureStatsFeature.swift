import Foundation

/// 截图统计 feature 只读取手动脚本落盘的数据；它不启动截图、不安装后台服务，也不申请权限。
public struct ActivityCaptureStatsFeature {
    public private(set) var todayStats: ActivityCaptureDailyStats

    private let rootDirectory: URL
    private let calendar: Calendar

    public init(rootDirectory: URL? = nil, now: Date = Date(), calendar: Calendar = .current) {
        self.rootDirectory = rootDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("JunimoActivityCaptures")
        self.calendar = calendar
        self.todayStats = Self.loadStats(rootDirectory: self.rootDirectory, now: now, calendar: calendar)
    }

    /// 业务语义：刷新只重新统计当天目录，不产生截图或外部进程副作用。
    public mutating func refresh(now: Date = Date()) {
        todayStats = Self.loadStats(rootDirectory: rootDirectory, now: now, calendar: calendar)
    }

    /// 业务语义：统计口径以当天目录为边界，避免 UI 把历史截图误认为今天的采样结果。
    private static func loadStats(rootDirectory: URL, now: Date, calendar: Calendar) -> ActivityCaptureDailyStats {
        let dateLabel = dayLabel(for: now, calendar: calendar)
        let dayDirectory = rootDirectory.appendingPathComponent(dateLabel, isDirectory: true)
        let fileManager = FileManager.default
        let imageURLs = imageFiles(in: dayDirectory, fileManager: fileManager)
        let imageNames = Set(imageURLs.map(\.lastPathComponent))
        let totalBytes = imageURLs.reduce(Int64(0)) { total, url in
            total + fileSize(url, fileManager: fileManager)
        }
        let indexRows = readIndexRows(from: dayDirectory.appendingPathComponent("index.csv"))
        let validRows = indexRows.filter { row in
            guard imageNames.contains(row.fileName), row.bytes > 0 else {
                return false
            }
            return row.width > 0 && row.height > 0
        }
        let missingRows = indexRows.filter { row in
            !imageNames.contains(row.fileName)
        }
        let latestURL = imageURLs.max { lhs, rhs in
            captureDate(for: lhs) ?? modificationDate(for: lhs, fileManager: fileManager) ?? .distantPast
                < captureDate(for: rhs) ?? modificationDate(for: rhs, fileManager: fileManager) ?? .distantPast
        }

        return ActivityCaptureDailyStats(
            dateLabel: dateLabel,
            directoryPath: dayDirectory.path,
            imageCount: imageURLs.count,
            indexedRowCount: indexRows.count,
            validIndexedFileCount: validRows.count,
            missingIndexedFileCount: missingRows.count,
            totalBytes: totalBytes,
            latestFileName: latestURL?.lastPathComponent ?? "",
            latestCaptureAt: latestURL.flatMap { captureDate(for: $0) ?? modificationDate(for: $0, fileManager: fileManager) }
        )
    }

    /// 业务语义：手动脚本按 yyyy-MM-dd 分目录，统计页和脚本必须使用同一日期口径。
    private static func dayLabel(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// 业务语义：只统计压缩后的可读图片，不把临时 raw 文件或索引文件算作截图。
    private static func imageFiles(in directory: URL, fileManager: FileManager) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "jpg" || ext == "jpeg"
        }
    }

    private struct IndexRow {
        var timestamp: String
        var fileName: String
        var width: Int
        var height: Int
        var bytes: Int64
    }

    /// 业务语义：index.csv 是手动截图脚本写下的轻量索引；解析失败的行不应该让统计页崩溃。
    private static func readIndexRows(from url: URL) -> [IndexRow] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return text
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 5 else {
                    return nil
                }
                return IndexRow(
                    timestamp: fields[0],
                    fileName: fields[1],
                    width: Int(fields[2]) ?? 0,
                    height: Int(fields[3]) ?? 0,
                    bytes: Int64(fields[4]) ?? 0
                )
            }
    }

    private static func fileSize(_ url: URL, fileManager: FileManager) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private static func modificationDate(for url: URL, fileManager: FileManager) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private static func captureDate(for url: URL) -> Date? {
        let stem = url.deletingPathExtension().lastPathComponent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.date(from: stem)
    }
}
