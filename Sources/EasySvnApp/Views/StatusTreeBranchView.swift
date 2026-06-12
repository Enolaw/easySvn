import SwiftUI

/// 可折叠的树形变更行（展开状态由 `expandedPaths` 控制）。
struct StatusTreeBranchView<Row: View>: View {
    let node: StatusTreeNode
    @Binding var expandedPaths: Set<String>
    @ViewBuilder let row: (StatusTreeNode) -> Row

    var body: some View {
        if node.isFolder {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedPaths.contains(node.path) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedPaths.insert(node.path)
                        } else {
                            expandedPaths.remove(node.path)
                        }
                    }
                )
            ) {
                ForEach(node.children) { child in
                    StatusTreeBranchView(node: child, expandedPaths: $expandedPaths, row: row)
                }
            } label: {
                row(node)
            }
        } else {
            row(node)
        }
    }
}
