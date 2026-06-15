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
    }

    static func evaluate(paths: [String], workingCopyRoot: URL) -> Evaluation {
        var allowed: [String] = []
        var rejected: [(path: String, reason: String)] = []

        for path in paths {
            if let reason = rejectionReason(for: path, workingCopyRoot: workingCopyRoot) {
                rejected.append((path, reason))
            } else {
                allowed.append(path)
            }
        }
        return Evaluation(allowed: allowed, rejected: rejected)
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
            return "目录包含超过 \(maxRecursiveFileCount) 个文件，请分批添加或配置忽略"
        }
        return nil
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
