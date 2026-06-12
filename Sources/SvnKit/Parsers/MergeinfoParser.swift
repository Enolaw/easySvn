import Foundation

/// 解析 `svn mergeinfo --show-revs` 输出的版本列表。
public enum MergeinfoParser {

    public static func parseRevisions(_ text: String) -> [Int] {
        text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                if trimmed.hasPrefix("r") {
                    return Int(trimmed.dropFirst())
                }
                return Int(trimmed)
            }
            .sorted()
    }
}
