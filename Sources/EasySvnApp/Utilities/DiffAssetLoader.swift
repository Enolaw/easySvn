import Foundation
import SvnKit

/// Diff 左右两侧内容的加载（图片 / 文本全文）。
enum DiffAssetLoader {

    struct DataPair {
        let left: Data
        let right: Data
        let leftLabel: String
        let rightLabel: String
    }

    static func loadDataPair(
        kind: ExternalDiffKind,
        workingCopy: WorkingCopy,
        client: SvnClient
    ) async throws -> DataPair {
        switch kind {
        case .workingCopy(let path):
            return try await loadWorkingCopyPair(path: path, workingCopy: workingCopy, client: client)
        case .revision(let revision, let logPath, let action):
            return try await loadRevisionPair(
                revision: revision,
                logPath: logPath,
                action: action,
                workingCopy: workingCopy,
                client: client
            )
        }
    }

    static func writeToTempFiles(_ pair: DataPair, pathHint: String) throws -> (URL, URL) {
        let sanitized = pathHint.replacingOccurrences(of: "/", with: "_")
        let leftURL = try makeTempFile(named: "left-\(sanitized)")
        let rightURL = try makeTempFile(named: "right-\(sanitized)")
        try pair.left.write(to: leftURL)
        try pair.right.write(to: rightURL)
        return (leftURL, rightURL)
    }

    private static func loadWorkingCopyPair(
        path: String,
        workingCopy: WorkingCopy,
        client: SvnClient
    ) async throws -> DataPair {
        let mineURL = workingCopy.directoryURL.appendingPathComponent(path)
        let left: Data
        do {
            left = try await client.cat(path: path, pegRevision: "BASE", in: workingCopy.directoryURL)
        } catch {
            left = Data()
        }
        let right: Data
        if FileManager.default.fileExists(atPath: mineURL.path) {
            right = try Data(contentsOf: mineURL)
        } else {
            right = Data()
        }
        return DataPair(left: left, right: right, leftLabel: "BASE", rightLabel: "工作副本")
    }

    private static func loadRevisionPair(
        revision: Int,
        logPath: String,
        action: SvnChangeAction?,
        workingCopy: WorkingCopy,
        client: SvnClient
    ) async throws -> DataPair {
        let info = try await client.info(at: workingCopy.directoryURL)
        let relative = RepositoryPathResolver.workingCopyRelativePath(logPath: logPath, wcInfo: info)
        let absolute = RepositoryPathResolver.absoluteFileURL(logPath: logPath, wcInfo: info)

        let left: Data
        if action == .added {
            left = Data()
        } else if revision > 1 {
            left = try await revisionContentIfPresent(
                client: client,
                relativePath: relative,
                absoluteURL: absolute,
                revision: revision - 1,
                workingCopy: workingCopy
            )
        } else {
            left = Data()
        }

        let right: Data
        if action == .deleted {
            right = Data()
        } else {
            right = try await revisionContentIfPresent(
                client: client,
                relativePath: relative,
                absoluteURL: absolute,
                revision: revision,
                workingCopy: workingCopy
            )
        }

        return DataPair(
            left: left,
            right: right,
            leftLabel: revisionLeftLabel(revision: revision, action: action, hasContent: !left.isEmpty),
            rightLabel: revisionRightLabel(revision: revision, action: action, hasContent: !right.isEmpty)
        )
    }

    static func revisionLeftLabel(
        revision: Int,
        action: SvnChangeAction?,
        hasContent: Bool
    ) -> String {
        if action == .added {
            return "（新增前无文件）"
        }
        if revision <= 1 {
            return "（空）"
        }
        let label = "r\(revision - 1)"
        return hasContent ? label : "\(label)（不存在）"
    }

    static func revisionRightLabel(
        revision: Int,
        action: SvnChangeAction?,
        hasContent: Bool
    ) -> String {
        if action == .deleted {
            return "（本版本已删除）"
        }
        let label = "r\(revision)"
        return hasContent ? label : "\(label)（不存在）"
    }

    /// 读取指定版本内容；路径在该版本不存在时返回空数据（不抛错）。
    private static func revisionContentIfPresent(
        client: SvnClient,
        relativePath: String?,
        absoluteURL: String,
        revision: Int,
        workingCopy: WorkingCopy
    ) async throws -> Data {
        do {
            return try await revisionContent(
                client: client,
                relativePath: relativePath,
                absoluteURL: absoluteURL,
                revision: revision,
                workingCopy: workingCopy
            )
        } catch let error as SvnError where error.isPathMissingInRevision {
            return Data()
        }
    }

    private static func revisionContent(
        client: SvnClient,
        relativePath: String?,
        absoluteURL: String,
        revision: Int,
        workingCopy: WorkingCopy
    ) async throws -> Data {
        if let relativePath {
            do {
                return try await client.cat(
                    path: relativePath,
                    pegRevision: String(revision),
                    in: workingCopy.directoryURL
                )
            } catch let error as SvnError where error.isPathMissingInRevision {
                throw error
            } catch {
                // 本地路径不可用时回退到仓库 URL
            }
        }
        return try await client.cat(absoluteURL, revision: String(revision))
    }

    private static func makeTempFile(named name: String) throws -> URL {
        let sanitized = name.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("easysvn-diff-\(UUID().uuidString)-\(sanitized)")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return url
    }
}
