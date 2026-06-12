import Foundation
import SvnKit

/// 将扁平变更列表构建为目录树。
enum StatusTreeBuilder {

    static func build(from entries: [SvnStatusEntry], sortOrder: StatusSortOrder) -> [StatusTreeNode] {
        var roots: [String: MutableNode] = [:]
        for entry in entries {
            insert(entry, roots: &roots)
        }
        return roots.values
            .map { $0.toTreeNode(sortOrder: sortOrder) }
            .sorted { sort($0, $1, order: sortOrder) }
    }

    private final class MutableNode {
        let path: String
        var entry: SvnStatusEntry?
        var children: [String: MutableNode] = [:]

        init(path: String) {
            self.path = path
        }

        func toTreeNode(sortOrder: StatusSortOrder) -> StatusTreeNode {
            StatusTreeNode(
                path: path,
                name: (path as NSString).lastPathComponent,
                entry: entry,
                children: children.values
                    .map { $0.toTreeNode(sortOrder: sortOrder) }
                    .sorted { StatusTreeBuilder.sort($0, $1, order: sortOrder) }
            )
        }
    }

    private static func insert(_ entry: SvnStatusEntry, roots: inout [String: MutableNode]) {
        let parts = entry.path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return }

        if roots[first] == nil {
            roots[first] = MutableNode(path: first)
        }
        var node = roots[first]!
        var pathParts = [first]

        if parts.count == 1 {
            node.entry = entry
            return
        }

        for part in parts.dropFirst() {
            pathParts.append(part)
            let fullPath = pathParts.joined(separator: "/")
            if node.children[part] == nil {
                node.children[part] = MutableNode(path: fullPath)
            }
            node = node.children[part]!
            if part == parts.last {
                node.entry = entry
            }
        }
    }

    private static func sort(_ lhs: StatusTreeNode, _ rhs: StatusTreeNode, order: StatusSortOrder) -> Bool {
        switch order {
        case .path:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .status:
            let lp = lhs.representativeStatus?.sortPriority ?? 99
            let rp = rhs.representativeStatus?.sortPriority ?? 99
            if lp != rp { return lp < rp }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
