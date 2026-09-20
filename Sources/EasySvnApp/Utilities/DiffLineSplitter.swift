import Foundation

/// 按常见换行符拆行。`svn diff` 的 hunk 头可能是 `\n`，而文件内容行是 `\r` / `\r\n`，
/// 只按 `\n` 拆会把后续增删行粘成一整段上下文。
enum DiffLineSplitter {

    static func split(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    static func decode(_ data: Data) -> String {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
