import Foundation

/// `svn resolve --accept` 的取值。
public enum SvnResolveAccept: String, Sendable, CaseIterable, Identifiable {
    case mineFull = "mine-full"
    case theirsFull = "theirs-full"
    case mineConflict = "mine-conflict"
    case theirsConflict = "theirs-conflict"
    case working
    case base

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mineFull: "采用我的（完整）"
        case .theirsFull: "采用对方（完整）"
        case .mineConflict: "采用我的（冲突块）"
        case .theirsConflict: "采用对方（冲突块）"
        case .working: "保留工作副本"
        case .base: "采用 BASE"
        }
    }
}
