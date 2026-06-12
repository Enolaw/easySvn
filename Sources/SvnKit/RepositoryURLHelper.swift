import Foundation

/// 仓库 URL 路径拼接与规范化。
public enum RepositoryURLHelper {

    public static func childURL(parent: String, name: String) -> String {
        let base = parent.hasSuffix("/") ? String(parent.dropLast()) : parent
        return "\(base)/\(name)"
    }

    public static func lastComponent(of url: String) -> String {
        let trimmed = url.hasSuffix("/") ? String(url.dropLast()) : url
        return URL(string: trimmed)?.lastPathComponent ?? trimmed
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
