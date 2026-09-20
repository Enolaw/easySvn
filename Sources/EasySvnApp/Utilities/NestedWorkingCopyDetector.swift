import Foundation

/// 嵌套工作副本（子目录内另有独立 `.svn`）。
struct NestedWorkingCopy: Sendable, Equatable, Identifiable {
    /// 相对于外层工作副本根的路径。
    let relativePath: String

    var id: String { relativePath }

    func directoryURL(in outerRoot: URL) -> URL {
        outerRoot.appendingPathComponent(relativePath).standardizedFileURL
    }
}

/// 扫描工作副本内嵌套的 SVN 工作副本根目录。
enum NestedWorkingCopyDetector {

    /// 在外层工作副本内查找嵌套 WC（不含外层根 `.svn`）。
    static func detect(in workingCopyRoot: URL) -> [NestedWorkingCopy] {
        let root = workingCopyRoot.standardizedFileURL
        let rootPath = root.path
        guard !rootPath.isEmpty else { return [] }

        let prefix = rootPath + "/"
        var relativeRoots: [String] = []

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return []
        }

        for case let itemURL as URL in enumerator {
            guard itemURL.lastPathComponent == ".svn" else { continue }
            guard (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            let parent = itemURL.deletingLastPathComponent().standardizedFileURL
            guard parent.path != rootPath else { continue }

            guard parent.path.hasPrefix(prefix) else { continue }
            let relative = String(parent.path.dropFirst(prefix.count))
            guard !relative.isEmpty else { continue }

            relativeRoots.append(WorkingCopyRelativePath.normalize(relative))
            enumerator.skipDescendants()
        }

        return Array(Set(relativeRoots))
            .sorted()
            .map { NestedWorkingCopy(relativePath: $0) }
    }

    /// 路径是否位于某个嵌套工作副本内部（含嵌套根本身）。
    static func isInsideNestedWorkingCopy(_ path: String, roots: some Collection<String>) -> Bool {
        let normalized = WorkingCopyRelativePath.normalize(path)
        return roots.contains { root in
            normalized == root || WorkingCopyRelativePath.isSameOrAncestor(root, of: normalized)
        }
    }

    /// 路径是否严格位于嵌套工作副本内部（不含嵌套根本身）。
    static func isStrictlyInsideNestedWorkingCopy(_ path: String, roots: some Collection<String>) -> Bool {
        let normalized = WorkingCopyRelativePath.normalize(path)
        return roots.contains { root in
            normalized != root && WorkingCopyRelativePath.isSameOrAncestor(root, of: normalized)
        }
    }

    /// 移除外层视角下嵌套 WC 内部的变更项（避免磁盘补全误判为未版本控制）。
    static func filterEntries<T>(
        _ entries: [T],
        path: (T) -> String,
        nestedRoots: some Collection<String>
    ) -> [T] {
        guard !nestedRoots.isEmpty else { return entries }
        return entries.filter { entry in
            !isStrictlyInsideNestedWorkingCopy(path(entry), roots: nestedRoots)
        }
    }

    /// 移除外层工作副本视角下的嵌套 `.svn` 元数据（常见于误复制工作副本目录）。
    static func removeMetadata(at directoryURL: URL) throws {
        let svnURL = directoryURL
            .appendingPathComponent(".svn", isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: svnURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NestedWorkingCopyError.metadataMissing
        }
        try FileManager.default.removeItem(at: svnURL)
    }
}

enum NestedWorkingCopyError: LocalizedError {
    case metadataMissing

    var errorDescription: String? {
        switch self {
        case .metadataMissing:
            "未找到嵌套 .svn 目录"
        }
    }
}
