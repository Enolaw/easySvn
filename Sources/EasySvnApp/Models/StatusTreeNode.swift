import Foundation
import SvnKit

/// 变更列表树节点（仅包含实际有变更的路径，不含空目录）。
struct StatusTreeNode: Identifiable, Sendable {
    /// 相对工作副本根的路径（根层节点为 `vnote/Package.swift` 等）。
    let path: String
    /// 当前层级显示名（路径最后一段）。
    let name: String
    /// 叶子或目录自身的 SVN 状态；纯分组目录为 nil。
    let entry: SvnStatusEntry?
    let children: [StatusTreeNode]

    var id: String { path }

    /// OutlineGroup 用：空目录返回 nil 表示叶子。
    var childNodes: [StatusTreeNode]? {
        children.isEmpty ? nil : children
    }

    var isFolder: Bool { !children.isEmpty }

    /// 用于排序/着色的代表性状态。
    var representativeStatus: SvnItemStatus? {
        if let entry { return entry.displayStatus }
        return children.compactMap(\.representativeStatus).min(by: { $0.sortPriority < $1.sortPriority })
    }

    /// 子树内所有叶子条目。
    var allEntries: [SvnStatusEntry] {
        if let entry, children.isEmpty { return [entry] }
        if let entry { return [entry] + children.flatMap(\.allEntries) }
        return children.flatMap(\.allEntries)
    }

    /// 收集子树中所有文件夹路径（用于默认全部展开）。
    static func allFolderPaths(in nodes: [StatusTreeNode]) -> Set<String> {
        var paths = Set<String>()
        func collect(_ nodes: [StatusTreeNode]) {
            for node in nodes where node.isFolder {
                paths.insert(node.path)
                collect(node.children)
            }
        }
        collect(nodes)
        return paths
    }
}
