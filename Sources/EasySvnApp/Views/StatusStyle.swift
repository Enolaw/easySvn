import SwiftUI
import SvnKit

/// 文件状态在 UI 中的展示样式（颜色/图标/文案遵循 SVN 客户端惯例）。
extension SvnItemStatus {

    var displayName: String {
        switch self {
        case .modified: "已修改"
        case .added: "新增"
        case .deleted: "已删除"
        case .conflicted: "冲突"
        case .unversioned: "未版本控制"
        case .missing: "缺失"
        case .replaced: "已替换"
        case .ignored: "已忽略"
        case .external: "外部引用"
        case .obstructed: "受阻"
        case .incomplete: "不完整"
        case .merged: "已合并"
        case .normal: "正常"
        case .none: "-"
        }
    }

    var color: Color {
        switch self {
        case .modified: .blue
        case .added: .green
        case .deleted, .missing: .red
        case .conflicted, .obstructed: .orange
        case .replaced: .purple
        case .unversioned, .ignored: .secondary
        default: .primary
        }
    }

    var symbolName: String {
        switch self {
        case .modified: "pencil.circle.fill"
        case .added: "plus.circle.fill"
        case .deleted, .missing: "minus.circle.fill"
        case .conflicted, .obstructed: "exclamationmark.triangle.fill"
        case .replaced: "arrow.triangle.2.circlepath.circle.fill"
        case .unversioned: "questionmark.circle"
        case .ignored: "eye.slash.circle"
        default: "circle"
        }
    }
}
