import Foundation
import SvnKit

/// 补全 svn status 未展开的未版本控制目录子项，供变更列表树形展示。
enum UnversionedDirectoryExpander {

    private static let blockedNames: Set<String> = [
        ".venv", "venv", "node_modules", "__pycache__", ".git",
        "DerivedData", "build", ".tox", ".pytest_cache"
    ]

    private static let maxExtraEntries = 2_000
    private static let maxExpansionPasses = 12

    /// 对 status 仅返回顶层 `? dir` 的目录，补全其下路径（优先 `svn status`，回退磁盘枚举）。
    static func expand(
        _ entries: [SvnStatusEntry],
        workingCopyRoot: URL,
        client: SvnClient? = nil,
        includeIgnored: Bool = false,
        nestedWorkingCopyRoots: Set<String> = []
    ) async throws -> [SvnStatusEntry] {
        var result = entries.map { $0.withNormalizedPath() }
        var pathSet = Set(result.map(\.path))
        var extraCount = 0

        for _ in 0..<maxExpansionPasses {
            let unversionedDirs = result.filter {
                $0.itemStatus == .unversioned && isDirectory($0.path, at: workingCopyRoot)
            }
            .filter { !hasStatusChild(path: $0.path, in: pathSet) }
            .sorted { $0.path.count < $1.path.count }

            if unversionedDirs.isEmpty { break }

            var progressed = false
            for dir in unversionedDirs {
                if extraCount >= maxExtraEntries { break }
                if NestedWorkingCopyDetector.isInsideNestedWorkingCopy(
                    dir.path,
                    roots: nestedWorkingCopyRoots
                ) {
                    continue
                }

                if let client {
                    let nested = try await client.status(
                        at: workingCopyRoot,
                        paths: [dir.path],
                        includeIgnored: includeIgnored
                    ).map { $0.withNormalizedPath() }
                    let scoped = nested.filter {
                        $0.path == dir.path || $0.path.hasPrefix(dir.path + "/")
                    }
                    let hasDetailedChildren = scoped.contains { $0.path.hasPrefix(dir.path + "/") }
                    let hasNonUnversioned = scoped.contains {
                        $0.itemStatus != .unversioned && $0.itemStatus != .ignored
                    }
                    if hasDetailedChildren || hasNonUnversioned {
                        for entry in scoped {
                            upsert(entry, into: &result, pathSet: &pathSet)
                            extraCount += 1
                        }
                        progressed = true
                        continue
                    }
                }

                let discovered = enumerate(
                    under: dir.path,
                    workingCopyRoot: workingCopyRoot,
                    remaining: maxExtraEntries - extraCount,
                    nestedWorkingCopyRoots: nestedWorkingCopyRoots
                )
                if discovered.isEmpty { continue }

                for path in discovered {
                    let normalized = WorkingCopyRelativePath.normalize(path)
                    guard !pathSet.contains(normalized) else { continue }
                    guard !hasVersionedCoverage(for: normalized, in: result) else { continue }
                    result.append(SvnStatusEntry(path: normalized, itemStatus: .unversioned, propsStatus: .none))
                    pathSet.insert(normalized)
                    extraCount += 1
                    progressed = true
                    if extraCount >= maxExtraEntries { break }
                }
            }

            if !progressed { break }
        }

        return pruneObsoletedUnversionedEntries(
            mergePreferringVersioned(result),
            workingCopyRoot: workingCopyRoot
        )
    }

    /// 移除已有受控后代时多余的未版本控制目录项（增量刷新后父目录仍可能残留）。
    static func pruneObsoletedUnversionedEntries(
        _ entries: [SvnStatusEntry],
        workingCopyRoot: URL
    ) -> [SvnStatusEntry] {
        let versioned = entries.filter { entry in
            switch entry.itemStatus {
            case .unversioned, .ignored, .none:
                return false
            default:
                return true
            }
        }
        guard !versioned.isEmpty else { return entries }

        return entries.filter { entry in
            guard entry.itemStatus == .unversioned else { return true }
            let covered = versioned.contains { versionedEntry in
                versionedEntry.path != entry.path
                    && WorkingCopyRelativePath.isSameOrAncestor(entry.path, of: versionedEntry.path)
            }
            return !covered
        }
    }

    static func mergePreferringVersioned(_ entries: [SvnStatusEntry]) -> [SvnStatusEntry] {
        var byPath: [String: SvnStatusEntry] = [:]
        for entry in entries {
            let key = WorkingCopyRelativePath.normalize(entry.path)
            if let existing = byPath[key] {
                byPath[key] = preferVersioned(existing, entry)
            } else {
                byPath[key] = entry
            }
        }
        return Array(byPath.values)
    }

    private static func preferVersioned(_ lhs: SvnStatusEntry, _ rhs: SvnStatusEntry) -> SvnStatusEntry {
        statusRank(rhs.itemStatus) > statusRank(lhs.itemStatus) ? rhs : lhs
    }

    private static func statusRank(_ status: SvnItemStatus) -> Int {
        switch status {
        case .unversioned, .ignored, .none, .normal:
            return 0
        default:
            return 1
        }
    }

    private static func upsert(
        _ entry: SvnStatusEntry,
        into result: inout [SvnStatusEntry],
        pathSet: inout Set<String>
    ) {
        let normalized = WorkingCopyRelativePath.normalize(entry.path)
        if let index = result.firstIndex(where: { WorkingCopyRelativePath.pathsEqual($0.path, normalized) }) {
            result[index] = preferVersioned(result[index], entry)
        } else {
            result.append(entry)
        }
        pathSet.insert(normalized)
    }

    private static func hasVersionedCoverage(for path: String, in entries: [SvnStatusEntry]) -> Bool {
        entries.contains { entry in
            switch entry.itemStatus {
            case .unversioned, .ignored, .none:
                return false
            default:
                return WorkingCopyRelativePath.isSameOrAncestor(entry.path, of: path)
            }
        }
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
        remaining: Int,
        nestedWorkingCopyRoots: Set<String> = []
    ) -> [String] {
        guard remaining > 0 else { return [] }
        if NestedWorkingCopyDetector.isInsideNestedWorkingCopy(rootPath, roots: nestedWorkingCopyRoots) {
            return []
        }
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
            if itemURL.lastPathComponent == ".svn" {
                enumerator.skipDescendants()
                continue
            }
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
