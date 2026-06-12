import Foundation

/// 统一 diff 单行类型。
enum DiffLineKind: Sendable {
    case header
    case hunk
    case addition
    case deletion
    case context
}

/// 统一 diff 的一行。
struct DiffLine: Identifiable, Sendable {
    let id: Int
    let kind: DiffLineKind
    let text: String
}

/// 解析 `svn diff` 输出的统一 diff 文本。
enum UnifiedDiffParser {

    static func parse(_ text: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            let kind: DiffLineKind
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("Index:")
                || line.hasPrefix("===") || line.hasPrefix("Property") {
                kind = .header
            } else if line.hasPrefix("@@") {
                kind = .hunk
            } else if line.hasPrefix("+") {
                kind = .addition
            } else if line.hasPrefix("-") {
                kind = .deletion
            } else if line.hasPrefix(" ") || line.isEmpty {
                kind = .context
            } else {
                kind = .header
            }
            lines.append(DiffLine(id: index, kind: kind, text: line))
        }
        return lines
    }
}
