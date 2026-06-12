import AppKit
import SwiftUI
import SvnKit

/// 选中工作副本的状态视图：信息头 + 变更文件列表 + 操作工具栏。
struct StatusListView: View {
    let workingCopy: WorkingCopy

    @StateObject private var viewModel = StatusViewModel()
    @State private var showCommitSheet = false
    @State private var revertCandidates: [String] = []
    @State private var showRevertConfirm = false
    @State private var diffPath: String?
    @State private var expandedPaths: Set<String> = []

    var body: some View {
        Group {
            if let message = viewModel.errorMessage {
                errorView(message)
            } else {
                VStack(spacing: 0) {
                    infoHeader
                    if hasBatchActions {
                        batchActionBar
                        Divider()
                    }
                    listHeader
                    Divider()
                    listContent
                }
            }
        }
        .navigationTitle(workingCopy.name)
        .toolbar { toolbarContent }
        .task(id: workingCopy.id) {
            await viewModel.refresh(workingCopy: workingCopy)
        }
        .sheet(isPresented: $showCommitSheet) {
            CommitSheet(
                fileCount: viewModel.selectedCommittablePaths.count,
                recentMessages: viewModel.recentCommitMessages
            ) { message in
                await viewModel.commit(workingCopy: workingCopy, message: message)
            }
        }
        .confirmationDialog(
            "还原 \(revertCandidates.count) 个文件的本地修改？",
            isPresented: $showRevertConfirm,
            titleVisibility: .visible
        ) {
            Button("还原修改", role: .destructive) {
                let paths = revertCandidates
                Task { await viewModel.revert(workingCopy: workingCopy, paths: paths) }
            }
        } message: {
            Text("本地修改将丢失，且无法撤销。")
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.operationError != nil },
                set: { if !$0 { viewModel.operationError = nil } }
            )
        ) {
            Button("好") { viewModel.operationError = nil }
        } message: {
            Text(viewModel.operationError ?? "")
        }
        .sheet(isPresented: Binding(
            get: { diffPath != nil },
            set: { if !$0 { diffPath = nil } }
        )) {
            if let path = diffPath {
                DiffView(
                    workingCopy: workingCopy,
                    source: .workingCopy(path: path),
                    title: path
                )
            }
        }
    }

    private var hasBatchActions: Bool {
        !viewModel.selectedUnversionedPaths.isEmpty || !viewModel.selectedMissingPaths.isEmpty
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                viewModel.selectAllSelectable()
            } label: {
                Label("全选", systemImage: "checkmark.circle")
            }
            .help("勾选全部变更项（⌘A）")
            .keyboardShortcut("a", modifiers: .command)
            .disabled(viewModel.isLoading || viewModel.entries.isEmpty)
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Picker("排序", selection: $viewModel.sortOrder) {
                    ForEach(StatusSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                Divider()
                Button("全选") { viewModel.selectAllSelectable() }
                Button("取消全选") { viewModel.deselectAll() }
            } label: {
                Label("排序：\(viewModel.sortOrder.label)", systemImage: "arrow.up.arrow.down")
            }
            .help("变更列表排序")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await viewModel.update(workingCopy: workingCopy) }
            } label: {
                Label("更新", systemImage: "arrow.down.circle")
            }
            .help("svn update（⌘U）")
            .keyboardShortcut("u", modifiers: .command)
            .disabled(viewModel.isLoading)

            Button {
                showCommitSheet = true
            } label: {
                Label("提交", systemImage: "paperplane")
            }
            .help("提交勾选的文件（⌘K）")
            .keyboardShortcut("k", modifiers: .command)
            .disabled(viewModel.isLoading || viewModel.selectedCommittablePaths.isEmpty)

            Button {
                Task { await viewModel.refresh(workingCopy: workingCopy) }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .help("刷新状态（⌘R）")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(viewModel.isLoading)
        }
    }

    // MARK: - 批量操作条

    private var batchActionBar: some View {
        HStack(spacing: 10) {
            if !viewModel.selectedUnversionedPaths.isEmpty {
                Text("未版本控制 \(viewModel.selectedUnversionedPaths.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("加入版本控制") {
                    let paths = viewModel.selectedUnversionedPaths
                    Task { await viewModel.addToVersionControl(workingCopy: workingCopy, paths: paths) }
                }
                .disabled(viewModel.isLoading)
                Button("加入并提交…") {
                    let paths = viewModel.selectedUnversionedPaths
                    Task {
                        if await viewModel.addUnversionedAndPrepareCommit(workingCopy: workingCopy, paths: paths) {
                            showCommitSheet = true
                        }
                    }
                }
                .disabled(viewModel.isLoading)
            }

            if !viewModel.selectedUnversionedPaths.isEmpty && !viewModel.selectedMissingPaths.isEmpty {
                Divider().frame(height: 16)
            }

            if !viewModel.selectedMissingPaths.isEmpty {
                Text("缺失 \(viewModel.selectedMissingPaths.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("从仓库恢复") {
                    let paths = viewModel.selectedMissingPaths
                    Task { await viewModel.restoreMissing(workingCopy: workingCopy, paths: paths) }
                }
                .disabled(viewModel.isLoading)
                Button("提交删除…") {
                    let paths = viewModel.selectedMissingPaths
                    Task {
                        if await viewModel.scheduleDeletionForMissing(workingCopy: workingCopy, paths: paths) {
                            showCommitSheet = true
                        }
                    }
                }
                .disabled(viewModel.isLoading)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - 信息头

    private var infoHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                if let info = viewModel.info {
                    Text(info.url.displayDecodedURL)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("版本 r\(info.revision)" + lastCommitText(info))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(workingCopy.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let message = viewModel.operationMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(2)
            }
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { viewModel.allSelectableSelected },
                set: { isOn in
                    if isOn {
                        viewModel.selectAllSelectable()
                    } else {
                        viewModel.deselectAll()
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(viewModel.entries.isEmpty || viewModel.isLoading)

            Button("全选") {
                viewModel.selectAllSelectable()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .disabled(viewModel.entries.isEmpty || viewModel.isLoading)

            Text("路径")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("状态")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35))
    }

    private func lastCommitText(_ info: SvnInfo) -> String {
        guard let revision = info.lastCommitRevision else { return "" }
        var text = " · 最后提交 r\(revision)"
        if let author = info.lastCommitAuthor {
            text += " by \(author)"
        }
        return text
    }

    private var treeRefreshKey: String {
        viewModel.entries
            .map { "\($0.path)|\($0.itemStatus.rawValue)" }
            .joined(separator: ";")
    }

    // MARK: - 文件列表

    @ViewBuilder
    private var listContent: some View {
        if viewModel.entries.isEmpty && !viewModel.isLoading {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("没有本地修改")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(viewModel.statusTree) { node in
                    StatusTreeBranchView(node: node, expandedPaths: $expandedPaths) { treeNode in
                        treeRow(for: treeNode)
                    }
                }
            }
            .listStyle(.inset)
            .onAppear(perform: expandAllFolders)
            .onChange(of: treeRefreshKey) { _ in
                expandAllFolders()
            }
        }
    }

    private func expandAllFolders() {
        expandedPaths = StatusTreeNode.allFolderPaths(in: viewModel.statusTree)
    }

    @ViewBuilder
    private func treeRow(for node: StatusTreeNode) -> some View {
        StatusTreeRow(
            node: node,
            isSelected: viewModel.hasSelectableContent(at: node.path)
                ? folderSelectionBinding(for: node.path)
                : nil
        )
        .contextMenu { rowMenu(for: node) }
        .onTapGesture(count: 2) {
            if let entry = node.entry, node.children.isEmpty, canShowDiff(entry) {
                diffPath = entry.path
            }
        }
    }

    private func folderSelectionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.isPathFullySelected(path) },
            set: { isOn in
                viewModel.setPathSelected(path, isOn: isOn)
            }
        )
    }

    @ViewBuilder
    private func rowMenu(for node: StatusTreeNode) -> some View {
        if node.isFolder {
            Button("全选此目录") {
                viewModel.setPathSelected(node.path, isOn: true)
            }
            Button("取消全选此目录") {
                viewModel.setPathSelected(node.path, isOn: false)
            }
            let missing = node.allEntries.filter { $0.itemStatus == .missing }.map(\.path)
            if !missing.isEmpty {
                Button("从仓库恢复（\(missing.count) 项）") {
                    Task { await viewModel.restoreMissing(workingCopy: workingCopy, paths: missing) }
                }
                Button("提交删除…", role: .destructive) {
                    Task {
                        if await viewModel.scheduleDeletionForMissing(workingCopy: workingCopy, paths: missing) {
                            showCommitSheet = true
                        }
                    }
                }
            }
            let unversioned = node.allEntries.filter { $0.itemStatus == .unversioned }.map(\.path)
            if !unversioned.isEmpty {
                Button("加入并提交…") {
                    Task {
                        if await viewModel.addUnversionedAndPrepareCommit(workingCopy: workingCopy, paths: unversioned) {
                            showCommitSheet = true
                        }
                    }
                }
            }
            Divider()
            Button("在 Finder 中显示") {
                let url = workingCopy.directoryURL.appendingPathComponent(node.path)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workingCopy.path)
                }
            }
        } else if let entry = node.entry {
            entryRowMenu(for: entry)
        }
    }

    @ViewBuilder
    private func entryRowMenu(for entry: SvnStatusEntry) -> some View {
        if canShowDiff(entry) {
            Button("查看差异") {
                diffPath = entry.path
            }
        }
        if entry.itemStatus == .unversioned {
            Button("加入版本控制") {
                Task { await viewModel.addToVersionControl(workingCopy: workingCopy, paths: [entry.path]) }
            }
            Button("加入并提交…") {
                Task {
                    if await viewModel.addUnversionedAndPrepareCommit(workingCopy: workingCopy, paths: [entry.path]) {
                        showCommitSheet = true
                    }
                }
            }
        }
        if entry.itemStatus == .missing {
            Button("从仓库恢复") {
                Task { await viewModel.restoreMissing(workingCopy: workingCopy, paths: [entry.path]) }
            }
            Button("提交删除…", role: .destructive) {
                Task {
                    if await viewModel.scheduleDeletionForMissing(workingCopy: workingCopy, paths: [entry.path]) {
                        showCommitSheet = true
                    }
                }
            }
        }
        if StatusViewModel.isCommittable(entry.itemStatus) || entry.itemStatus == .conflicted {
            Button("还原修改…", role: .destructive) {
                revertCandidates = [entry.path]
                showRevertConfirm = true
            }
        }
        Divider()
        Button("在 Finder 中显示") {
            let url = workingCopy.directoryURL.appendingPathComponent(entry.path)
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workingCopy.path)
            }
        }
    }

    private func canShowDiff(_ entry: SvnStatusEntry) -> Bool {
        switch entry.itemStatus {
        case .modified, .added, .deleted, .replaced, .merged: true
        default: false
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("重试") {
                Task { await viewModel.refresh(workingCopy: workingCopy) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 树形变更列表行。
struct StatusTreeRow: View {
    let node: StatusTreeNode
    let isSelected: Binding<Bool>?

    private var presentation: (icon: String, color: Color, label: String) {
        if node.isFolder {
            let count = node.allEntries.count
            if let entry = node.entry {
                return (entry.itemStatus.symbolName, entry.itemStatus.color, entry.itemStatus.displayName)
            }
            let status = node.representativeStatus
            return (
                "folder.fill",
                status?.color ?? .secondary,
                count > 1 ? "\(count) 项" : (status?.displayName ?? "目录")
            )
        }
        if let entry = node.entry {
            return (entry.itemStatus.symbolName, entry.itemStatus.color, entry.itemStatus.displayName)
        }
        return ("doc", .secondary, "-")
    }

    var body: some View {
        let style = presentation
        HStack(spacing: 10) {
            if let isSelected {
                Toggle("", isOn: isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            } else {
                Spacer().frame(width: 16)
            }
            Image(systemName: style.icon)
                .foregroundStyle(style.color)
                .frame(width: 18)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(style.label)
                .font(.caption)
                .foregroundStyle(style.color)
                .frame(width: 72, alignment: .trailing)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(style.color.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 1)
    }
}
