import Foundation

/// SVN 检出深度（`--depth`）。
public enum SvnDepth: String, Sendable, CaseIterable, Identifiable {
    case infinity
    case immediates
    case files
    case empty

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .infinity: "完整递归"
        case .immediates: "仅直接子项"
        case .files: "仅文件"
        case .empty: "仅目录（空）"
        }
    }
}
