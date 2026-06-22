import Foundation

/// 仓库 URL 路径拼接与规范化。
public enum RepositoryURLHelper {

    /// 将 URL 中的 `%E4%B8%AD` 等形式解码为可读中文（已解码则原样返回）。
    public static func displayDecoded(_ url: String) -> String {
        var result = url
        while let decoded = result.removingPercentEncoding, decoded != result {
            result = decoded
        }
        return result
    }

    public static func childURL(parent: String, name: String) -> String {
        let base = parent.hasSuffix("/") ? String(parent.dropLast()) : parent
        return "\(base)/\(name)"
    }

    public static func lastComponent(of url: String) -> String {
        var trimmed = url
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let slashIndex = trimmed.lastIndex(of: "/") else {
            return displayDecoded(trimmed)
        }
        let component = String(trimmed[trimmed.index(after: slashIndex)...])
        return displayDecoded(component)
    }

    public static func parentURL(of url: String) -> String? {
        var trimmed = url
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let slashIndex = trimmed.lastIndex(of: "/") else { return nil }
        let parent = String(trimmed[..<slashIndex])
        // 不要越过协议部分，如 "https:/" 或 "file://"。
        if parent.isEmpty || parent.hasSuffix(":/") || parent.hasSuffix(":") {
            return nil
        }
        if parent == trimmed { return nil }
        return parent
    }
}
