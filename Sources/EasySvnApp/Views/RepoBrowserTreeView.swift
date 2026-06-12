import SwiftUI
import SvnKit

/// 仓库目录树（懒加载展开）。
struct RepoBrowserTreeView: View {
    @ObservedObject var viewModel: RepoBrowserViewModel
    var onViewLog: ((RepoTreeNode) -> Void)?

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedURL },
            set: { newValue in
                guard let newValue else { return }
                viewModel.selectDeferred(newValue)
            }
        )) {
            if !viewModel.rootURL.isEmpty {
                RepoTreeBranch(
                    node: RepoTreeNode(rootURL: viewModel.rootURL),
                    viewModel: viewModel,
                    onViewLog: onViewLog,
                    depth: 0
                )
            }
        }
        .listStyle(.sidebar)
    }
}

private struct RepoTreeBranch: View {
    let node: RepoTreeNode
    @ObservedObject var viewModel: RepoBrowserViewModel
    var onViewLog: ((RepoTreeNode) -> Void)?
    let depth: Int

    private var children: [RepoTreeNode] {
        viewModel.treeChildren[node.url] ?? []
    }

    private var isExpanded: Bool {
        viewModel.expandedURLs.contains(node.url)
    }

    var body: some View {
        if node.kind == .dir {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isExpanded },
                    set: { expanded in
                        viewModel.toggleExpandDeferred(node.url, expanded: expanded)
                    }
                ),
                content: {
                    ForEach(children) { child in
                        if child.kind == .dir {
                            RepoTreeBranch(
                                node: child,
                                viewModel: viewModel,
                                onViewLog: onViewLog,
                                depth: depth + 1
                            )
                        } else {
                            treeRow(child)
                        }
                    }
                },
                label: {
                    treeRow(node)
                }
            )
        } else {
            treeRow(node)
        }
    }

    private func treeRow(_ item: RepoTreeNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind == .dir ? "folder" : "doc")
                .foregroundStyle(item.kind == .dir ? .blue : .secondary)
            Text(item.name)
                .lineLimit(1)
        }
        .tag(item.url)
        .contextMenu {
            Button("查看日志…") {
                onViewLog?(item)
            }
            if item.kind == .file {
                Button("查看内容") {
                    viewModel.selectDeferred(item.url)
                }
            } else {
                Button("打开") {
                    viewModel.selectDeferred(item.url)
                }
            }
        }
    }
}
