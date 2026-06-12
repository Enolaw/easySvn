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

    /// 属性（如 svn:ignore）已修改。
    public var hasModifiedProps: Bool {
        propsStatus == .modified
    }

    /// 仅属性变更、内容未变（对应 `svn status` 第二列 `M`）。
    public var isPropsOnlyModified: Bool {
        switch itemStatus {
        case .normal, .none:
            return hasModifiedProps
        default:
            return false
        }
    }

    /// 列表排序/展示用的状态（属性独占变更时视为 modified）。
    public var displayStatus: SvnItemStatus {
        isPropsOnlyModified ? .modified : itemStatus
    }

    /// 内容维度是否可提交。
    public static func isCommittableItem(_ status: SvnItemStatus) -> Bool {
        switch status {
        case .modified, .added, .deleted, .replaced: true
        default: false
        }
    }

    /// 是否应纳入提交（含仅属性变更的目录/文件）。
    public var isCommittable: Bool {
        Self.isCommittableItem(itemStatus) || hasModifiedProps
    }
}
