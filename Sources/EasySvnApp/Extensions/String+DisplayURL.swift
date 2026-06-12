import Foundation

extension String {

    /// 将 URL 中的 `%E4%B8%AD` 等形式解码为可读中文（已解码则原样返回）。
    var displayDecodedURL: String {
        removingPercentEncoding ?? self
    }
}
