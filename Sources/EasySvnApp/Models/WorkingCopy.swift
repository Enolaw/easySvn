import Foundation

/// 侧边栏中的一个工作副本书签。
struct WorkingCopy: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String

    var directoryURL: URL { URL(fileURLWithPath: path) }

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = WorkingCopyPathNormalizer.normalize(path)
    }

    init(directoryURL: URL) {
        let normalized = WorkingCopyPathNormalizer.normalize(directoryURL.path)
        self.init(name: directoryURL.lastPathComponent, path: normalized)
    }
}
