import Foundation

/// 未版本控制路径加入前的安全检查（避免误 add .venv 等巨型目录）。
enum UnversionedAddPolicy {

    private static let blockedNames: Set<String> = [
        ".venv", "venv", "node_modules", "__pycache__", ".git",
        "DerivedData", "build", ".tox", ".pytest_cache"
    ]

    private static let maxRecursiveFileCount = 200

    struct Evaluation {
        let allowed: [String]
        let rejected: [(path: String, reason: String)]
        /// 因文件过多而自动改为添加内部 dist 目录的路径映射（原路径 → dist 路径）。
        let redirected: [(from: String, to: String)]
    }

    static func evaluate(paths: [String], workingCopyRoot: URL) -> Evaluation {
        var allowed: [String] = []
        var rejected: [(path: String, reason: String)] = []
        var redirected: [(from: String, to: String)] = []

        for path in paths {
            if let reason = rejectionReason(for: path, workingCopyRoot: workingCopyRoot) {
                if reason == tooManyFilesReason,
                   let distPath = distArchivePath(for: path, workingCopyRoot: workingCopyRoot),
                   !allowed.contains(distPath) {
                    allowed.append(distPath)
                    redirected.append((path, distPath))
                } else {
                    rejected.append((path, reason))
                }
            } else {
                allowed.append(path)
            }
        }
        return Evaluation(allowed: allowed, rejected: rejected, redirected: redirected)
    }

    /// 将大量跳过项汇总为简短说明，避免弹窗渲染过多行导致卡死。
    static func formatRejectedSummary(
        title: String?,
        rejected: [(path: String, reason: String)],
        maxExamplesPerReason: Int = 3
    ) -> String {
        guard !rejected.isEmpty else { return title ?? "" }
        var lines: [String] = []
        if let title, !title.isEmpty {
            lines.append(title)
            lines.append("")
        }
        lines.append("共 \(rejected.count) 项被跳过：")

        let grouped = Dictionary(grouping: rejected, by: \.reason)
        for (reason, items) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
            lines.append("• \(items.count) 项：\(reason)")
            for path in items.prefix(maxExamplesPerReason) {
                lines.append("  \(path)")
            }
            let remaining = items.count - maxExamplesPerReason
            if remaining > 0 {
                lines.append("  … 另有 \(remaining) 项")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 汇总因文件过多而自动改为添加 dist 的说明。
    static func formatRedirectedSummary(redirected: [(from: String, to: String)]) -> String {
        guard !redirected.isEmpty else { return "" }
        var lines = ["已自动改为添加 dist 目录（原目录文件过多）："]
        for (from, to) in redirected {
            lines.append("• \(from)")
            lines.append("  → \(to)")
        }
        return lines.joined(separator: "\n")
    }

    private static var tooManyFilesReason: String {
        "目录包含超过 \(maxRecursiveFileCount) 个文件，请分批添加或配置忽略"
    }

    private static func rejectionReason(for path: String, workingCopyRoot: URL) -> String? {
        let components = path.split(separator: "/").map(String.init)
        for name in components {
            if blockedNames.contains(name) {
                return "「\(name)」建议加入 svn:ignore，不宜直接提交"
            }
        }

        let url = workingCopyRoot.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        // Tag 归档场景需提交 dist 构建产物，不对 dist 目录做文件数上限。
        if components.contains("dist") {
            return nil
        }

        let fileCount = recursiveFileCount(at: url, limit: maxRecursiveFileCount + 1)
        if fileCount > maxRecursiveFileCount {
            return tooManyFilesReason
        }
        return nil
    }

    /// Tag 归档：在版本目录内查找应提交的 dist 路径，优先 `production/dist` / `prod/dist`。
    private static let preferredDistSuffixes = ["production/dist", "prod/dist", "test/dist"]

    private static func distArchivePath(for path: String, workingCopyRoot: URL) -> String? {
        for suffix in preferredDistSuffixes {
            let preferred = "\(path)/\(suffix)"
            if directoryExists(preferred, at: workingCopyRoot) {
                return preferred
            }
        }

        let baseURL = workingCopyRoot.appendingPathComponent(path)
        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var candidates: [String] = []
        let rootPrefix = workingCopyRoot.path + "/"
        for case let dirURL as URL in enumerator {
            guard dirURL.lastPathComponent == "dist",
                  (try? dirURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  dirURL.path.hasPrefix(rootPrefix) else {
                continue
            }
            candidates.append(String(dirURL.path.dropFirst(rootPrefix.count)))
        }
        return preferDistPaths(candidates).first
    }

    private static func preferDistPaths(_ candidates: [String]) -> [String] {
        guard !candidates.isEmpty else { return [] }
        for suffix in preferredDistSuffixes {
            if let preferred = candidates.first(where: { $0.hasSuffix(suffix) }) {
                return [preferred]
            }
        }
        let sorted = candidates.sorted { $0.count < $1.count }
        var result: [String] = []
        for candidate in sorted {
            if result.contains(where: { candidate.hasPrefix($0 + "/") }) { continue }
            result.removeAll { $0.hasPrefix(candidate + "/") }
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }
        return result
    }

    private static func directoryExists(_ path: String, at workingCopyRoot: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let url = workingCopyRoot.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func recursiveFileCount(at url: URL, limit: Int) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
                if count > limit {
                    return count
                }
            }
        }
        return count
    }
}
