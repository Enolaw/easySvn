import Foundation

/// `svn mergeinfo --show-revs` 的查询类型。
public enum SvnMergeinfoKind: String, Sendable {
    case merged
    case eligible
}
