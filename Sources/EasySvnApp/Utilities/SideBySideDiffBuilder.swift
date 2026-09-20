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
    let leftInlineRanges: [InlineHighlightRange]
    let rightLineNumber: Int?
    let rightText: String?
    let rightHighlight: SideBySideHighlight
    let rightInlineRanges: [InlineHighlightRange]
    let isHunkHeader: Bool
    let hunkLabel: String?

    init(
        id: Int,
        leftLineNumber: Int?,
        leftText: String?,
        leftHighlight: SideBySideHighlight,
        rightLineNumber: Int?,
        rightText: String?,
        rightHighlight: SideBySideHighlight,
        isHunkHeader: Bool = false,
        hunkLabel: String? = nil
    ) {
        self.id = id
        self.leftLineNumber = leftLineNumber
        self.leftText = leftText
        self.leftHighlight = leftHighlight
        self.rightLineNumber = rightLineNumber
        self.rightText = rightText
        self.rightHighlight = rightHighlight
        self.isHunkHeader = isHunkHeader
        self.hunkLabel = hunkLabel

        if leftHighlight == .deletion,
           rightHighlight == .addition,
           let leftText,
           let rightText {
            let pair = InlineDiffHighlighter.changedRanges(left: leftText, right: rightText)
            leftInlineRanges = pair.left
            rightInlineRanges = pair.right
        } else {
            leftInlineRanges = []
            rightInlineRanges = []
        }
    }
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
            rightHighlight: SideBySideHighlight,
            isHunkHeader: Bool = false,
            hunkLabel: String? = nil
        ) {
            rows.append(SideBySideRow(
                id: rowID,
                leftLineNumber: leftLineNumber,
                leftText: leftText,
                leftHighlight: leftHighlight,
                rightLineNumber: rightLineNumber,
                rightText: rightText,
                rightHighlight: rightHighlight,
                isHunkHeader: isHunkHeader,
                hunkLabel: hunkLabel
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
                    rightText: nil,
                    rightHighlight: .empty,
                    isHunkHeader: true,
                    hunkLabel: hunkDisplayLabel(line.text)
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

    /// 全文左右并排：按行对齐后再做行内高亮。
    static func buildFromFullText(left: String, right: String) -> [SideBySideRow] {
        let leftLines = DiffLineSplitter.split(left)
        let rightLines = DiffLineSplitter.split(right)
        return align(leftLines: leftLines, rightLines: rightLines)
    }

    static func changeBlockIDs(in rows: [SideBySideRow]) -> [Int] {
        var ids: [Int] = []
        var inBlock = false
        for row in rows {
            if row.isHunkHeader {
                inBlock = false
                continue
            }
            let isChange = row.leftHighlight == .deletion || row.rightHighlight == .addition
            if isChange {
                if !inBlock {
                    ids.append(row.id)
                    inBlock = true
                }
            } else {
                inBlock = false
            }
        }
        return ids
    }

    static func hunkDisplayLabel(_ line: String) -> String {
        if let parsed = parseHunkHeader(line) {
            return "旧版本第 \(parsed.oldStart) 行 · 新版本第 \(parsed.newStart) 行"
        }
        return line
    }

    private static let naiveAlignLineLimit = 15_000

    private static func align(leftLines: [String], rightLines: [String]) -> [SideBySideRow] {
        if leftLines.count > naiveAlignLineLimit || rightLines.count > naiveAlignLineLimit {
            return naiveAlign(leftLines: leftLines, rightLines: rightLines)
        }

        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in rightLines.difference(from: leftLines) {
            switch change {
            case .remove(let offset, _, _):
                removedOffsets.insert(offset)
            case .insert(let offset, _, _):
                insertedOffsets.insert(offset)
            }
        }

        var rows: [SideBySideRow] = []
        var pendingDeletes: [(Int, String)] = []
        var pendingAdds: [(Int, String)] = []
        var oldIndex = 0
        var newIndex = 0
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

        while oldIndex < leftLines.count || newIndex < rightLines.count {
            let removing = oldIndex < leftLines.count && removedOffsets.contains(oldIndex)
            let inserting = newIndex < rightLines.count && insertedOffsets.contains(newIndex)

            if removing {
                pendingDeletes.append((oldIndex + 1, leftLines[oldIndex]))
                oldIndex += 1
            }
            if inserting {
                pendingAdds.append((newIndex + 1, rightLines[newIndex]))
                newIndex += 1
            }
            if !removing && !inserting {
                flushPending()
                if oldIndex < leftLines.count, newIndex < rightLines.count {
                    appendRow(
                        leftLineNumber: oldIndex + 1,
                        leftText: leftLines[oldIndex],
                        leftHighlight: .context,
                        rightLineNumber: newIndex + 1,
                        rightText: rightLines[newIndex],
                        rightHighlight: .context
                    )
                    oldIndex += 1
                    newIndex += 1
                } else if oldIndex < leftLines.count {
                    pendingDeletes.append((oldIndex + 1, leftLines[oldIndex]))
                    oldIndex += 1
                } else if newIndex < rightLines.count {
                    pendingAdds.append((newIndex + 1, rightLines[newIndex]))
                    newIndex += 1
                }
            }
        }
        flushPending()
        return rows
    }

    private static func naiveAlign(leftLines: [String], rightLines: [String]) -> [SideBySideRow] {
        let count = max(leftLines.count, rightLines.count)
        return (0..<count).map { index in
            let left = index < leftLines.count ? leftLines[index] : nil
            let right = index < rightLines.count ? rightLines[index] : nil
            let changed = left != right
            return SideBySideRow(
                id: index,
                leftLineNumber: left == nil ? nil : index + 1,
                leftText: left,
                leftHighlight: changed && left != nil ? .deletion : (left == nil ? .empty : .context),
                rightLineNumber: right == nil ? nil : index + 1,
                rightText: right,
                rightHighlight: changed && right != nil ? .addition : (right == nil ? .empty : .context)
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
