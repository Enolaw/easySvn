import Foundation
import SvnKit

/// 日志分页缓存键。
struct LogCacheKey: Hashable, Codable {
    let repositoryKey: String
    let revisionRange: String
    let limit: Int
    let verbose: Bool
}

private struct LogCachePage: Codable {
    let cachedAt: Date
    let entries: [SvnLogEntry]
}

/// 已拉取日志的本地缓存（加速二次浏览）。
actor LogCacheStore {

    static let shared = LogCacheStore()

    private let maxAge: TimeInterval = 24 * 60 * 60
    private let directoryURL: URL
    private var memory: [LogCacheKey: LogCachePage] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = base.appendingPathComponent("easySvn/log-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func load(key: LogCacheKey) -> [SvnLogEntry]? {
        if let page = memory[key], !isExpired(page) {
            return page.entries
        }
        guard let page = loadFromDisk(key: key), !isExpired(page) else {
            return nil
        }
        memory[key] = page
        return page.entries
    }

    func store(key: LogCacheKey, entries: [SvnLogEntry]) {
        let page = LogCachePage(cachedAt: Date(), entries: entries)
        memory[key] = page
        saveToDisk(key: key, page: page)
    }

    func invalidate(repositoryKey: String) {
        memory = memory.filter { $0.key.repositoryKey != repositoryKey }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return
        }
        let prefix = fileNamePrefix(for: repositoryKey)
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func repositoryKey(for workingCopy: WorkingCopy, info: SvnInfo?) -> String {
        let raw = info?.repositoryRoot.isEmpty == false
            ? info?.repositoryRoot
            : (info?.url.isEmpty == false ? info?.url : workingCopy.path)
        return raw ?? workingCopy.path
    }

    private func isExpired(_ page: LogCachePage) -> Bool {
        Date().timeIntervalSince(page.cachedAt) > maxAge
    }

    private func fileURL(for key: LogCacheKey) -> URL {
        let name = "\(fileNamePrefix(for: key.repositoryKey))-\(key.revisionRange)-\(key.limit)-\(key.verbose).json"
            .replacingOccurrences(of: ":", with: "_")
        return directoryURL.appendingPathComponent(name)
    }

    private func fileNamePrefix(for repositoryKey: String) -> String {
        String(repositoryKey.hashValue.magnitude)
    }

    private func loadFromDisk(key: LogCacheKey) -> LogCachePage? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LogCachePage.self, from: data)
    }

    private func saveToDisk(key: LogCacheKey, page: LogCachePage) {
        let url = fileURL(for: key)
        guard let data = try? JSONEncoder().encode(page) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
