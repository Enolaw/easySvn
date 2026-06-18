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
        let trimmed = url.hasSuffix("/") ? String(url.dropLast()) : url
        let component = URL(string: trimmed)?.lastPathComponent ?? trimmed
        return displayDecoded(component)
    }

    public static func parentURL(of url: String) -> String? {
        let trimmed = url.hasSuffix("/") ? String(url.dropLast()) : url
        guard let url = URL(string: trimmed) else { return nil }
        let parent = url.deletingLastPathComponent()
        var parentString = parent.absoluteString
        if parentString.hasSuffix("/") {
            parentString = String(parentString.dropLast())
        }
        if parentString == trimmed { return nil }
        return parentString
    }
}
