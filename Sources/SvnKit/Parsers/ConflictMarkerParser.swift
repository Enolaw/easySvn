import Foundation

/// 冲突标记块（`<<<<<<<` / `=======` / `>>>>>>>`）。
public struct ConflictHunk: Identifiable, Equatable, Sendable {
    public let id: Int
    public let mineText: String
    public let theirsText: String

    public init(id: Int, mineText: String, theirsText: String) {
        self.id = id
        self.mineText = mineText
        self.theirsText = theirsText
    }
}

public enum ConflictHunkChoice: Equatable, Sendable {
    case mine
    case theirs
    case unresolved
}

/// 解析 SVN 冲突标记并合成结果文本。
public enum ConflictMarkerParser {

    public static func parse(_ text: String) -> [ConflictHunk] {
        var hunks: [ConflictHunk] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        var hunkID = 0

        while index < lines.count {
            guard lines[index].hasPrefix("<<<<<<<") else {
                index += 1
                continue
            }
            index += 1
            var mineLines: [String] = []
            while index < lines.count, !lines[index].hasPrefix("=======") {
                mineLines.append(lines[index])
                index += 1
            }
            guard index < lines.count, lines[index].hasPrefix("=======") else { break }
            index += 1
            var theirsLines: [String] = []
            while index < lines.count, !lines[index].hasPrefix(">>>>>>>") {
                theirsLines.append(lines[index])
                index += 1
            }
            guard index < lines.count, lines[index].hasPrefix(">>>>>>>") else { break }
            index += 1
            hunks.append(ConflictHunk(
                id: hunkID,
                mineText: mineLines.joined(separator: "\n"),
                theirsText: theirsLines.joined(separator: "\n")
            ))
            hunkID += 1
        }
        return hunks
    }

    public static func mergedText(
        original: String,
        hunks: [ConflictHunk],
        choices: [Int: ConflictHunkChoice]
    ) -> String {
        guard !hunks.isEmpty else { return original }

        var output: [String] = []
        let lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        var hunkIndex = 0

        while index < lines.count {
            if lines[index].hasPrefix("<<<<<<<"), hunkIndex < hunks.count {
                let hunk = hunks[hunkIndex]
                let choice = choices[hunk.id] ?? .unresolved
                switch choice {
                case .mine:
                    if !hunk.mineText.isEmpty { output.append(hunk.mineText) }
                case .theirs:
                    if !hunk.theirsText.isEmpty { output.append(hunk.theirsText) }
                case .unresolved:
                    output.append("<<<<<<<")
                    output.append(hunk.mineText)
                    output.append("=======")
                    output.append(hunk.theirsText)
                    output.append(">>>>>>>")
                }
                index += 1
                while index < lines.count, !lines[index].hasPrefix(">>>>>>>") {
                    index += 1
                }
                if index < lines.count { index += 1 }
                hunkIndex += 1
            } else {
                output.append(lines[index])
                index += 1
            }
        }
        return output.joined(separator: "\n")
    }
}
