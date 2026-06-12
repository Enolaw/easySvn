import Foundation

/// 未版本控制路径加入前的安全检查（避免误 add .venv 等巨型目录）。
enum UnversionedAddPolicy {

    private static let blockedNames: Set<String> = [
        ".venv", "venv", "node_modules", "__pycache__", ".git",
        "DerivedData", "build", "dist", ".tox", ".pytest_cache"
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
