import Foundation

/// 从仓库 URL 提取 Keychain 分区用的 realm 标识。
public enum SvnRealm {

    /// 生成凭据存储键：优先使用 `scheme://host:port`，`file://` 使用规范化路径。
    public static func from(repositoryURL: String) -> String {
        let trimmed = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.hasPrefix("file://") {
            return trimmed
        }

        guard let url = URL(string: trimmed), let host = url.host else {
            return trimmed
        }

        let scheme = url.scheme ?? "https"
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        let defaultPort = (scheme == "https") ? 443 : 80
        return "\(scheme)://\(host):\(defaultPort)"
    }
}
