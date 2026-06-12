import Foundation

/// 文件/属性状态，对应 `svn status --xml` 中 wc-status 的 item / props 取值。
public enum SvnItemStatus: String, Sendable, Equatable, CaseIterable {
    case none
    case normal
    case added
    case missing
    case incomplete
    case deleted
    case replaced
    case modified
    case merged
    case conflicted
    case obstructed
    case ignored
    case external
    case unversioned
}

/// `svn status` 的单条结果。
public struct SvnStatusEntry: Sendable, Equatable {
    /// 相对于 status 目标的路径。
    public let path: String
    /// 文件内容状态。
    public let itemStatus: SvnItemStatus
    /// 属性状态。
    public let propsStatus: SvnItemStatus
    /// 工作副本版本号（未版本控制时为 nil）。
    public let revision: Int?
    /// 最后提交版本号。
    public let commitRevision: Int?
    /// 最后提交作者。
    public let commitAuthor: String?
    /// 是否存在树冲突。
    public let isTreeConflicted: Bool
    /// 是否由复制而来。
    public let isCopied: Bool
    /// 工作副本目录是否被锁定（需要 cleanup）。
    public let isWCLocked: Bool

    public init(
        path: String,
        itemStatus: SvnItemStatus,
        propsStatus: SvnItemStatus,
        revision: Int? = nil,
        commitRevision: Int? = nil,
        commitAuthor: String? = nil,
        isTreeConflicted: Bool = false,
        isCopied: Bool = false,
        isWCLocked: Bool = false
    ) {
        self.path = path
        self.itemStatus = itemStatus
        self.propsStatus = propsStatus
        self.revision = revision
        self.commitRevision = commitRevision
        self.commitAuthor = commitAuthor
        self.isTreeConflicted = isTreeConflicted
        self.isCopied = isCopied
        self.isWCLocked = isWCLocked
    }
}
