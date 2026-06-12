import Foundation

enum SideBySideHighlight: Sendable, Equatable {
    case context
    case deletion
    case addition
    case empty
}

/// 并排 diff 的一行（左旧右新）。
struct SideBySideRow: Identifiable, Sendable, Equatable {
    let id: Int
    let leftLineNumber: Int?
    let leftText: String?
    let leftHighlight: SideBySideHighlight
    let rightLineNumber: Int?
    let rightText: String?
    let rightHighlight: SideBySideHighlight
}

/// 将统一 diff 转为左右并排行。
enum SideBySideDiffBuilder {

    static func build(from lines: [DiffLine]) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        var leftNum = 1
        var rightNum = 1
        var pendingDeletes: [(Int, String)] = []
        var pendingAdds: [(Int, String)] = []
        var rowID = 0

        func appendRow(
            leftLineNumber: Int?,
            leftText: String?,
            leftHighlight: SideBySideHighlight,
            rightLineNumber: Int?,
            rightText: String?,
            rightHighlight: SideBySideHighlight
        ) {
            rows.append(SideBySideRow(
                id: rowID,
                leftLineNumber: leftLineNumber,
                leftText: leftText,
                leftHighlight: leftHighlight,
                rightLineNumber: rightLineNumber,
                rightText: rightText,
                rightHighlight: rightHighlight
            ))
            rowID += 1
        }

        func flushPending() {
            while !pendingDeletes.isEmpty || !pendingAdds.isEmpty {
                let left = pendingDeletes.isEmpty ? nil : pendingDeletes.removeFirst()
                let right = pendingAdds.isEmpty ? nil : pendingAdds.removeFirst()
                appendRow(
                    leftLineNumber: left?.0,
                    leftText: left?.1,
                    leftHighlight: left == nil ? .empty : .deletion,
                    rightLineNumber: right?.0,
                    rightText: right?.1,
                    rightHighlight: right == nil ? .empty : .addition
                )
            }
        }

        for line in lines {
            switch line.kind {
            case .header:
                continue
            case .hunk:
                flushPending()
                if let parsed = parseHunkHeader(line.text) {
                    leftNum = parsed.oldStart
                    rightNum = parsed.newStart
                }
                appendRow(
                    leftLineNumber: nil,
                    leftText: nil,
                    leftHighlight: .empty,
                    rightLineNumber: nil,
                    rightText: line.text,
                    rightHighlight: .context
                )
            case .context:
                flushPending()
                let text = stripDiffPrefix(line.text)
                appendRow(
                    leftLineNumber: leftNum,
                    leftText: text,
                    leftHighlight: .context,
                    rightLineNumber: rightNum,
                    rightText: text,
                    rightHighlight: .context
                )
                leftNum += 1
                rightNum += 1
            case .deletion:
                let text = stripDiffPrefix(line.text)
                pendingDeletes.append((leftNum, text))
                leftNum += 1
            case .addition:
                let text = stripDiffPrefix(line.text)
                pendingAdds.append((rightNum, text))
                rightNum += 1
            }
        }
        flushPending()
        return rows
    }

    /// 全文左右并排（无 diff 高亮，用于图片之外的纯文本全文对比）。
    static func buildFromFullText(left: String, right: String) -> [SideBySideRow] {
        let leftLines = left.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let rightLines = right.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let count = max(leftLines.count, rightLines.count)
        return (0..<count).map { index in
            let l = index < leftLines.count ? leftLines[index] : nil
            let r = index < rightLines.count ? rightLines[index] : nil
            let changed = l != r
            return SideBySideRow(
                id: index,
                leftLineNumber: l == nil ? nil : index + 1,
                leftText: l,
                leftHighlight: changed && r != nil ? .deletion : .context,
                rightLineNumber: r == nil ? nil : index + 1,
                rightText: r,
                rightHighlight: changed && l != nil ? .addition : .context
            )
        }
    }

    private static func stripDiffPrefix(_ line: String) -> String {
        guard let first = line.first, first == " " || first == "+" || first == "-" else {
            return line
        }
        return String(line.dropFirst())
    }

    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, newStart: Int)? {
        // @@ -10,7 +10,8 @@
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line),
              let oldStart = Int(line[oldRange]),
              let newStart = Int(line[newRange]) else {
            return nil
        }
        return (oldStart, newStart)
    }
}
