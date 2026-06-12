import Foundation

/// svn:ignore 与取消添加（revert）的路径辅助。
enum IgnorePathHelper {

    /// 将路径转为 (父目录, 忽略模式名)。
    static func ignoreSpec(for path: String) -> (parent: String, pattern: String)? {
        let ns = path as NSString
        let pattern = ns.lastPathComponent
        let parent = ns.deletingLastPathComponent
        guard !pattern.isEmpty else { return nil }
        if parent.isEmpty || parent == "." {
            return (".", pattern)
        }
        return (parent, pattern)
    }

    /// 合并多条已添加路径为少量 revert 根（如整个 `.venv` 只 revert 一次）。
    static func collapseRevertRoots(paths: [String]) -> [String] {
        var roots = Set<String>()
        for path in paths {
            if let root = blockedAncestorRoot(in: path) {
                roots.insert(root)
            } else {
                roots.insert(path)
            }
        }
        return minimizeRoots(Array(roots))
    }

    /// 是否包含大量已添加的虚拟环境文件（界面卡顿提示用）。
    static func massAddedVenvRoots(in entries: [(path: String, status: String)]) -> [String] {
        var counts: [String: Int] = [:]
        for entry in entries where entry.status == "added" {
            if let root = blockedAncestorRoot(in: entry.path) {
                counts[root, default: 0] += 1
            }
        }
        return counts.filter { $0.value >= 3 }.map(\.key).sorted()
    }

    private static let blockedNames: Set<String> = [
        ".venv", "venv", "node_modules", "__pycache__"
    ]

    private static func blockedAncestorRoot(in path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        for (index, part) in parts.enumerated() where blockedNames.contains(part) {
            return parts[0...index].joined(separator: "/")
        }
        return nil
    }

    private static func minimizeRoots(_ paths: [String]) -> [String] {
        let sorted = paths.sorted { $0.count < $1.count }
        var result: [String] = []
        for path in sorted {
            if !result.contains(where: { path.hasPrefix($0 + "/") }) {
                result.append(path)
            }
        }
        return result
    }
}
