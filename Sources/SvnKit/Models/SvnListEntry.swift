import Foundation

/// `svn list` 的单条结果（仓库浏览器的数据基础）。
public struct SvnListEntry: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case file
        case dir
    }

    /// 相对名称（目录条目不带末尾斜杠）。
    public let name: String
    public let kind: Kind
    /// 文件大小（目录为 nil）。
    public let size: Int?
    public let commitRevision: Int?
    public let commitAuthor: String?
    public let commitDate: Date?

    public init(
        name: String,
        kind: Kind,
        size: Int? = nil,
        commitRevision: Int? = nil,
        commitAuthor: String? = nil,
        commitDate: Date? = nil
    ) {
        self.name = name
        self.kind = kind
        self.size = size
        self.commitRevision = commitRevision
        self.commitAuthor = commitAuthor
        self.commitDate = commitDate
    }
}
