import Foundation

/// 仓库路径与工作副本路径之间的转换。
public enum RepositoryPathResolver {

    /// 规范化日志中的仓库路径（去掉 leading `/`）。
    public static func normalizedRepoPath(_ path: String) -> String {
        var normalized = path
        if normalized.hasPrefix("/") {
            normalized = String(normalized.dropFirst())
        }
        return normalized
    }

    /// 将日志 verbose 输出的仓库路径转为工作副本内相对路径。
    ///
    /// 例：日志路径 `/12_组/09_王/卡面交接/a.md`，工作副本 `^/12_组/09_王` → `卡面交接/a.md`
    public static func workingCopyRelativePath(logPath: String, wcInfo: SvnInfo) -> String? {
        let repoPath = normalizedRepoPath(logPath)
        guard let relativeURL = wcInfo.relativeURL else {
            return repoPath
        }

        var wcPrefix = relativeURL
        if wcPrefix.hasPrefix("^/") {
            wcPrefix = String(wcPrefix.dropFirst(2))
        } else if wcPrefix.hasPrefix("^") {
            wcPrefix = String(wcPrefix.dropFirst())
        } else if wcPrefix.hasPrefix("/") {
            wcPrefix = String(wcPrefix.dropFirst())
        }

        if repoPath == wcPrefix {
            return "."
        }

        let prefix = wcPrefix + "/"
        guard repoPath.hasPrefix(prefix) else {
            return nil
        }
        return String(repoPath.dropFirst(prefix.count))
    }

    /// 由仓库根 URL + 日志路径构造文件的完整仓库 URL（本地无文件时也可 diff）。
    public static func absoluteFileURL(logPath: String, wcInfo: SvnInfo) -> String {
        let repoPath = normalizedRepoPath(logPath)
        let root = wcInfo.repositoryRoot
        if root.hasSuffix("/") {
            return root + repoPath
        }
        return root + "/" + repoPath
    }
}
