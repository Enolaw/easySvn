import Foundation

/// 常见可预览图片格式（DF-3）。
enum ImageFileDetector {
    private static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif", "ico"
    ]

    static func isImage(_ path: String) -> Bool {
        let ext = path.split(separator: ".").last.map { String($0).lowercased() } ?? ""
        return extensions.contains(ext)
    }
}
