import Foundation
import SvnKit

/// 仓库浏览器树节点（懒加载子目录）。
struct RepoTreeNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: String
    let kind: SvnListEntry.Kind
    let commitRevision: Int?
    let commitDate: Date?

    init(entry: SvnListEntry, parentURL: String) {
        self.name = entry.name
        self.url = RepositoryURLHelper.childURL(parent: parentURL, name: entry.name)
        self.id = url
        self.kind = entry.kind
        self.commitRevision = entry.commitRevision
        self.commitDate = entry.commitDate
    }

    init(rootURL: String, name: String = "/") {
        self.name = name
        self.url = rootURL
        self.id = rootURL
        self.kind = .dir
        self.commitRevision = nil
        self.commitDate = nil
    }
}
