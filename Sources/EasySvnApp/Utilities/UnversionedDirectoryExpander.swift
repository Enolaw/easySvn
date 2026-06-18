import Foundation
import SvnKit

/// 补全 svn status 未展开的未版本控制目录子项，供变更列表树形展示。
enum UnversionedDirectoryExpander {

    private static let blockedNames: Set<String> = [
        ".venv", "venv", "node_modules", "__pycache__", ".git",
        "DerivedData", "build", ".tox", ".pytest_cache"
    ]

    private static let maxExtraEntries = 2_000

    /// 对 status 仅返回顶层 `? dir` 的目录，递归补全其下路径（仅用于展示）。
    static func expand(_ entries: [SvnStatusEntry], workingCopyRoot: URL) -> [SvnStatusEntry] {
        var pathSet = Set(entries.map(\.path))
        var result = entries
        var extraCount = 0

        let unversionedDirs = entries.filter {
            $0.itemStatus == .unversioned && isDirectory($0.path, at: workingCopyRoot)
        }

        for dir in unversionedDirs {
            guard !hasStatusChild(path: dir.path, in: pathSet) else { continue }
            let discovered = enumerate(
                under: dir.path,
                workingCopyRoot: workingCopyRoot,
                remaining: maxExtraEntries - extraCount
            )
            for path in discovered where !pathSet.contains(path) {
                result.append(SvnStatusEntry(path: path, itemStatus: .unversioned, propsStatus: .none))
                pathSet.insert(path)
                extraCount += 1
                if extraCount >= maxExtraEntries { return result }
            }
        }
        return result
    }

    private static func hasStatusChild(path: String, in pathSet: Set<String>) -> Bool {
        let prefix = path + "/"
        return pathSet.contains { $0.hasPrefix(prefix) }
    }

    private static func isDirectory(_ path: String, at workingCopyRoot: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let url = workingCopyRoot.appendingPathComponent(path).standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func enumerate(
        under rootPath: String,
        workingCopyRoot: URL,
        remaining: Int
    ) -> [String] {
        guard remaining > 0 else { return [] }
        let rootURL = workingCopyRoot.appendingPathComponent(rootPath).standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths: [String] = []
        let rootPrefix = rootURL.path + "/"

        for case let itemURL as URL in enumerator {
            if blockedNames.contains(itemURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            let standardized = itemURL.standardizedFileURL
            let values = try? standardized.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            guard values?.isDirectory == true || values?.isRegularFile == true else { continue }

            guard standardized.path.hasPrefix(rootPrefix) else { continue }
            let relative = String(standardized.path.dropFirst(rootPrefix.count))
            guard !relative.isEmpty else { continue }
            paths.append(rootPath + "/" + relative)
            if paths.count >= remaining { break }
        }
        return paths
    }
}
