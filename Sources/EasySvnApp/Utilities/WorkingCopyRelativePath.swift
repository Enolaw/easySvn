import Foundation

/// 工作副本内相对路径规范化（macOS 文件名 NFD 与 svn 输出 NFC 对齐）。
enum WorkingCopyRelativePath {

    /// 统一为 NFC，避免同一文件在列表中出现两条不同路径。
    static func normalize(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    /// 按磁盘实际路径解析（若存在），并规范为 NFC。
    static func resolvingOnDisk(_ path: String, workingCopyRoot: URL) -> String {
        let root = workingCopyRoot.standardizedFileURL
        let fileURL = root.appendingPathComponent(path).standardizedFileURL
        let prefix = root.path + "/"
        guard fileURL.path.hasPrefix(prefix) else { return normalize(path) }
        let relative = String(fileURL.path.dropFirst(prefix.count))
        return normalize(relative)
    }

    static func pathsEqual(_ lhs: String, _ rhs: String) -> Bool {
        normalize(lhs) == normalize(rhs)
    }

    static func isSameOrAncestor(_ ancestor: String, of path: String) -> Bool {
        let a = normalize(ancestor)
        let p = normalize(path)
        return p == a || p.hasPrefix(a + "/")
    }
}
