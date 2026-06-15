import Foundation

enum WorkingCopyPathNormalizer {

    /// 统一工作副本路径，避免 `/private/Users/...` 等别名导致 svn 识别失败。
    static func normalize(_ path: String) -> String {
        var normalized = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .path

        if normalized.hasPrefix("/private/Users/") {
            let withoutPrivate = String(normalized.dropFirst("/private".count))
            if FileManager.default.fileExists(atPath: withoutPrivate) {
                normalized = withoutPrivate
            }
        }
        return normalized
    }
}
