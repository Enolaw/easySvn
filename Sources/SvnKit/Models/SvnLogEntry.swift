import Foundation

/// 日志中单个文件的变更动作。
public enum SvnChangeAction: String, Sendable, Equatable, Codable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case replaced = "R"
}

/// 日志中的单条变更路径。
public struct SvnChangedPath: Sendable, Equatable, Codable {
    public let action: SvnChangeAction
    /// 仓库内路径（如 `/trunk/foo.txt`）。
    public let path: String
    /// node 类型（file / dir）。
    public let kind: String?
    /// 复制来源（分支/重命名时存在）。
    public let copyFromPath: String?
    public let copyFromRevision: Int?

    public init(
        action: SvnChangeAction,
        path: String,
        kind: String? = nil,
        copyFromPath: String? = nil,
        copyFromRevision: Int? = nil
    ) {
        self.action = action
        self.path = path
        self.kind = kind
        self.copyFromPath = copyFromPath
        self.copyFromRevision = copyFromRevision
    }
}

/// `svn log` 的单条日志。
public struct SvnLogEntry: Sendable, Equatable, Codable {
    public let revision: Int
    public let author: String?
    public let date: Date?
    public let message: String
    /// 变更文件列表（仅 `--verbose` 时有值）。
    public let changedPaths: [SvnChangedPath]

    public init(
        revision: Int,
        author: String? = nil,
        date: Date? = nil,
        message: String = "",
        changedPaths: [SvnChangedPath] = []
    ) {
        self.revision = revision
        self.author = author
        self.date = date
        self.message = message
        self.changedPaths = changedPaths
    }
}
