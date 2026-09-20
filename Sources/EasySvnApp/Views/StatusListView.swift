import AppKit
import SwiftUI
import SvnKit

/// 选中工作副本的状态视图：信息头 + 变更文件列表 + 操作工具栏。
struct StatusListView: View {
    let workingCopy: WorkingCopy
    var refreshToken: UUID = UUID()

    @EnvironmentObject private var authStore: AuthSettingsStore
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var store: WorkingCopyStore
    @StateObject private var viewModel = StatusViewModel()
    @State private var externalDiffError: String?
    @State private var fileWatcher = WorkingCopyFileWatcher()
    @State private var showCommitSheet = false
    @State private var revertCandidates: [String] = []
    @State private var showRevertConfirm = false
    @State private var diffPath: String?
    @State private var conflictPresentation: ConflictPresentation?
    @State private var expandedPaths: Set<String> = []
    @State private var nestedRemovalCandidate: NestedWorkingCopy?

    private struct ConflictPresentation: Identifiable {
        let id = UUID()
        let path: String
        let isTreeConflict: Bool
    }

    private var statusTaskID: String {
        "\(workingCopy.id.uuidString)-\(refreshToken.uuidString)"
    }

    var body: some View {
        Group {
            if let message = viewModel.errorMessage {
                errorView(message)
            } else {
                VStack(spacing: 0) {
                    infoHeader
                    if !viewModel.conflictedEntries.isEmpty {
                        conflictActionBar
                        Divider()
                    }
                    if !viewModel.massAddedVenvRoots.isEmpty {
                        venvWarningBar
                        Divider()
                    }
                    if !viewModel.nestedWorkingCopies.isEmpty {
                        nestedWorkingCopyWarningBar
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
        .task(id: statusTaskID) {
            viewModel.configure(authStore: authStore, appSettings: appSettings)
            startFileWatcherIfNeeded()
            viewModel.requestRefresh(workingCopy: workingCopy)
        }
        .onChange(of: appSettings.showIgnored) { _ in
            viewModel.requestRefresh(workingCopy: workingCopy)
        }
        .onDisappear {
            fileWatcher.stop()
            viewModel.cancelRefresh()
        }
        .onChange(of: authStore.autoRefreshEnabled) { _ in
            startFileWatcherIfNeeded()
        }
        .alert(
            "移除此嵌套 .svn？",
            isPresented: Binding(
                get: { nestedRemovalCandidate != nil },
                set: { if !$0 { nestedRemovalCandidate = nil } }
            ),
            presenting: nestedRemovalCandidate
        ) { nested in
            Button("删除 .svn", role: .destructive) {
                Task {
                    await viewModel.removeNestedWorkingCopyMetadata(
                        nested: nested,
                        in: workingCopy
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: { nested in
            Text(
                """
                通常是因为复制文件夹时把 .svn 一并复制进来了。

                删除「\(nested.relativePath)」内的 .svn 后，该目录会对此工作副本显示为未版本控制文件，而不会自动关联到当前仓库。

                若这些文件属于其他 SVN 路径（如卡面业务），请优先使用「添加为工作副本」单独管理，而不是删除 .svn。
                """
            )
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
        .alert("无法打开外部工具", isPresented: Binding(
            get: { externalDiffError != nil },
            set: { if !$0 { externalDiffError = nil } }
        )) {
            Button("好") { externalDiffError = nil }
        } message: {
            Text(externalDiffError ?? "")
        }
        .sheet(isPresented: Binding(
            get: { viewModel.operationError != nil },
            set: { if !$0 { viewModel.operationError = nil } }
        )) {
            OperationNoticeSheet(
                title: "操作失败",
                message: viewModel.operationError ?? ""
            ) {
                viewModel.operationError = nil
            }
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
        .sheet(item: $conflictPresentation) { item in
            ConflictMergeView(
                workingCopy: workingCopy,
                path: item.path,
                isTreeConflict: item.isTreeConflict
            ) {
                await viewModel.refresh(workingCopy: workingCopy)
            }
        }
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
            Toggle(isOn: $appSettings.showIgnored) {
                Label("显示已忽略", systemImage: "eye.slash")
            }
            .help("在变更列表中显示 svn:ignore 匹配的文件")
            .disabled(viewModel.isLoading)
        }

        if !viewModel.conflictedEntries.isEmpty {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $viewModel.showConflictsOnly) {
                    Label("仅冲突", systemImage: "exclamationmark.triangle")
                }
                .help("仅显示冲突文件")
            }
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

            if viewModel.isLoading {
                Button {
                    viewModel.cancelRefresh()
                } label: {
                    Label("取消", systemImage: "xmark.circle")
                }
                .help("取消状态扫描")
            } else {
                Button {
                    viewModel.requestRefresh(workingCopy: workingCopy)
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新状态（⌘R）")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    // MARK: - 冲突操作条

    private var conflictActionBar: some View {
        HStack(spacing: 10) {
            Label("\(viewModel.conflictedEntries.count) 个冲突", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            Button("打开合并…") {
                if let first = viewModel.conflictedEntries.first {
                    openConflict(first)
                }
            }
            .disabled(viewModel.isLoading)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - 嵌套工作副本提示

    private var nestedWorkingCopyWarningBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.orange)
                Text("检测到嵌套工作副本（常见于复制文件夹时带入了 .svn）。外层无法准确显示其内部状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(viewModel.nestedWorkingCopies) { nested in
                HStack(spacing: 12) {
                    Text(nested.relativePath)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("添加为工作副本") {
                        store.add(directoryURL: nested.directoryURL(in: workingCopy.directoryURL))
                    }
                    Button("删除 .svn", role: .destructive) {
                        nestedRemovalCandidate = nested
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - .venv 误添加提示

    private var venvWarningBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("检测到 `.venv` 已被加入版本控制，会导致扫描极慢")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(viewModel.massAddedVenvRoots, id: \.self) { root in
                Button("取消并忽略") {
                    Task { await viewModel.fixMassAddedVenv(workingCopy: workingCopy, root: root) }
                }
                .disabled(viewModel.isLoading)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - 选中项操作条（单一入口，按状态分组）

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Text(viewModel.selectionSummary.summaryText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .animation(.none, value: viewModel.selectionSummary.summaryText)
            Spacer()
            if viewModel.selectionSummary.categoryCount == 1 {
                selectionPrimaryButton
                selectionSecondaryMenu
            } else {
                selectionActionsMenu(label: "操作选中项…")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }

    @ViewBuilder
    private var selectionPrimaryButton: some View {
        if !viewModel.selectedUnversionedPaths.isEmpty {
            Button("加入版本控制") {
                let paths = viewModel.selectedUnversionedPaths
                Task { await viewModel.addToVersionControl(workingCopy: workingCopy, paths: paths) }
            }
            .disabled(viewModel.isLoading)
        } else if !viewModel.selectedAddedPaths.isEmpty {
            Button("撤销添加") {
                let paths = viewModel.selectedAddedPaths
                Task { await viewModel.cancelScheduledAdd(workingCopy: workingCopy, paths: paths) }
            }
            .disabled(viewModel.isLoading)
        } else if !viewModel.selectedMissingPaths.isEmpty {
            Button("从仓库恢复") {
                let paths = viewModel.selectedMissingPaths
                Task { await viewModel.restoreMissing(workingCopy: workingCopy, paths: paths) }
            }
            .disabled(viewModel.isLoading)
        } else if !viewModel.selectedIgnoredPaths.isEmpty {
            Button("取消忽略") {
                let paths = viewModel.selectedIgnoredPaths
                Task { await viewModel.removeFromIgnoreList(workingCopy: workingCopy, paths: paths) }
            }
            .disabled(viewModel.isLoading)
        }
    }

    @ViewBuilder
    private var selectionSecondaryMenu: some View {
        if !viewModel.selectedUnversionedPaths.isEmpty {
            Menu("更多") {
                unversionedActionButtons(paths: viewModel.selectedUnversionedPaths, includeAdd: false)
            }
            .disabled(viewModel.isLoading)
        } else if !viewModel.selectedAddedPaths.isEmpty {
            Menu("更多") {
                addedActionButtons(paths: viewModel.selectedAddedPaths, includeRevert: false)
            }
            .disabled(viewModel.isLoading)
        } else if !viewModel.selectedMissingPaths.isEmpty {
            Menu("更多") {
                missingActionButtons(paths: viewModel.selectedMissingPaths, includeRestore: false)
            }
            .disabled(viewModel.isLoading)
        } else if !viewModel.selectedIgnoredPaths.isEmpty {
            EmptyView()
        }
    }

    private func selectionActionsMenu(label: String) -> some View {
        Menu {
            if !viewModel.selectedUnversionedPaths.isEmpty {
                Section("未版本控制（\(viewModel.selectedUnversionedPaths.count)）") {
                    unversionedActionButtons(paths: viewModel.selectedUnversionedPaths, includeAdd: true)
                }
            }
            if !viewModel.selectedAddedPaths.isEmpty {
                Section("新增（\(viewModel.selectedAddedPaths.count)）") {
                    addedActionButtons(paths: viewModel.selectedAddedPaths, includeRevert: true)
                }
            }
            if !viewModel.selectedMissingPaths.isEmpty {
                Section("缺失（\(viewModel.selectedMissingPaths.count)）") {
                    missingActionButtons(paths: viewModel.selectedMissingPaths, includeRestore: true)
                }
            }
            if !viewModel.selectedIgnoredPaths.isEmpty {
                Section("已忽略（\(viewModel.selectedIgnoredPaths.count)）") {
                    ignoredActionButtons(paths: viewModel.selectedIgnoredPaths, includeRemove: true)
                }
            }
        } label: {
            Text(label)
        }
        .disabled(viewModel.isLoading)
    }

    @ViewBuilder
    private func unversionedActionButtons(paths: [String], includeAdd: Bool) -> some View {
        if includeAdd {
            Button("加入版本控制") {
                Task { await viewModel.addToVersionControl(workingCopy: workingCopy, paths: paths) }
            }
        }
        Button("加入并提交…") {
            Task {
                if await viewModel.addUnversionedAndPrepareCommit(workingCopy: workingCopy, paths: paths) {
                    showCommitSheet = true
                }
            }
        }
        Button("忽略") {
            Task { await viewModel.addToIgnoreList(workingCopy: workingCopy, paths: paths) }
        }
    }

    @ViewBuilder
    private func addedActionButtons(paths: [String], includeRevert: Bool) -> some View {
        if includeRevert {
            Button("撤销添加") {
                Task { await viewModel.cancelScheduledAdd(workingCopy: workingCopy, paths: paths) }
            }
        }
        Button("忽略") {
            Task { await viewModel.addToIgnoreList(workingCopy: workingCopy, paths: paths) }
        }
    }

    @ViewBuilder
    private func missingActionButtons(paths: [String], includeRestore: Bool) -> some View {
        if includeRestore {
            Button("从仓库恢复") {
                Task { await viewModel.restoreMissing(workingCopy: workingCopy, paths: paths) }
            }
        }
        Button("提交删除…", role: .destructive) {
            Task {
                if await viewModel.scheduleDeletionForMissing(workingCopy: workingCopy, paths: paths) {
                    showCommitSheet = true
                }
            }
        }
    }

    @ViewBuilder
    private func ignoredActionButtons(paths: [String], includeRemove: Bool) -> some View {
        if includeRemove {
            Button("取消忽略") {
                Task { await viewModel.removeFromIgnoreList(workingCopy: workingCopy, paths: paths) }
            }
        }
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
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    if let message = viewModel.loadingMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
            .map { "\($0.path)|\($0.itemStatus.rawValue)|\($0.propsStatus.rawValue)" }
            .joined(separator: ";")
    }

    // MARK: - 文件列表

    @ViewBuilder
    private var listContent: some View {
        if viewModel.isLoading && viewModel.sortedEntries.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text(viewModel.loadingMessage ?? "正在扫描变更…")
                    .foregroundStyle(.secondary)
                Button("取消") {
                    viewModel.cancelRefresh()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.sortedEntries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: viewModel.showConflictsOnly ? "checkmark.circle" : "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text(viewModel.showConflictsOnly ? "没有冲突文件" : "没有本地修改")
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
            .safeAreaInset(edge: .top, spacing: 0) {
                selectionActionInset
                    .animation(.easeInOut(duration: 0.18), value: viewModel.selectionSummary.hasActions)
            }
            .animation(.none, value: viewModel.selectionSummary.totalCount)
            .onAppear(perform: expandAllFolders)
            .onChange(of: treeRefreshKey) { _ in
                expandAllFolders()
            }
        }
    }

    @ViewBuilder
    private var selectionActionInset: some View {
        if viewModel.selectionSummary.hasActions {
            VStack(spacing: 0) {
                selectionActionBar
                Divider()
            }
            .background(.background)
            .transition(.opacity)
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
            guard let entry = node.entry, node.children.isEmpty else { return }
            if StatusViewModel.isConflicted(entry) {
                openConflict(entry)
            } else if canShowDiff(entry) {
                openDiff(for: entry.path)
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
                Section("缺失（\(missing.count)）") {
                    Button("从仓库恢复") {
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
            }
            let unversioned = node.allEntries.filter { $0.itemStatus == .unversioned }.map(\.path)
            if !unversioned.isEmpty {
                Section("未版本控制（\(unversioned.count)）") {
                    Button("加入版本控制") {
                        Task { await viewModel.addToVersionControl(workingCopy: workingCopy, paths: unversioned) }
                    }
                    Button("加入并提交…") {
                        Task {
                            if await viewModel.addUnversionedAndPrepareCommit(workingCopy: workingCopy, paths: unversioned) {
                                showCommitSheet = true
                            }
                        }
                    }
                    Button("忽略") {
                        Task { await viewModel.addToIgnoreList(workingCopy: workingCopy, paths: unversioned) }
                    }
                }
            }
            let added = node.allEntries.filter { $0.itemStatus == .added }.map(\.path)
            if !added.isEmpty {
                Section("新增（\(added.count)）") {
                    Button("撤销添加") {
                        Task { await viewModel.cancelScheduledAdd(workingCopy: workingCopy, paths: added) }
                    }
                    Button("忽略") {
                        Task { await viewModel.addToIgnoreList(workingCopy: workingCopy, paths: added) }
                    }
                }
            }
            let ignored = node.allEntries.filter { $0.itemStatus == .ignored }.map(\.path)
            if !ignored.isEmpty {
                Section("已忽略（\(ignored.count)）") {
                    Button("取消忽略") {
                        Task { await viewModel.removeFromIgnoreList(workingCopy: workingCopy, paths: ignored) }
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

    private func openConflict(_ entry: SvnStatusEntry) {
        conflictPresentation = ConflictPresentation(
            path: entry.path,
            isTreeConflict: entry.isTreeConflicted
        )
    }

    @ViewBuilder
    private func entryRowMenu(for entry: SvnStatusEntry) -> some View {
        if StatusViewModel.isConflicted(entry) {
            Button("解决冲突…") {
                openConflict(entry)
            }
            Button("采用我的") {
                Task { await viewModel.resolveConflict(workingCopy: workingCopy, path: entry.path, accept: .mineFull) }
            }
            Button("采用对方") {
                Task { await viewModel.resolveConflict(workingCopy: workingCopy, path: entry.path, accept: .theirsFull) }
            }
            Button("标记已解决") {
                Task { await viewModel.markConflictResolved(workingCopy: workingCopy, path: entry.path) }
            }
            Divider()
        }
        if canShowDiff(entry) {
            Button(appSettings.preferExternalDiff && appSettings.hasExternalDiffTool ? "使用外部工具查看差异" : "查看差异") {
                openDiff(for: entry.path)
            }
            if appSettings.hasExternalDiffTool && !appSettings.preferExternalDiff {
                Button("使用外部工具查看差异") {
                    Task { await openExternalDiff(path: entry.path) }
                }
            } else if appSettings.hasExternalDiffTool {
                Button("在内置查看器中查看") {
                    diffPath = entry.path
                }
            }
        }
        if entry.itemStatus == .added {
            Section("新增") {
                Button("撤销添加") {
                    Task { await viewModel.cancelScheduledAdd(workingCopy: workingCopy, paths: [entry.path]) }
                }
                Button("忽略") {
                    Task { await viewModel.addToIgnoreList(workingCopy: workingCopy, paths: [entry.path]) }
                }
            }
        }
        if entry.itemStatus == .unversioned {
            Section("未版本控制") {
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
                Button("忽略") {
                    Task { await viewModel.addToIgnoreList(workingCopy: workingCopy, paths: [entry.path]) }
                }
            }
        }
        if entry.itemStatus == .missing {
            Section("缺失") {
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
        }
        if entry.itemStatus == .ignored {
            Section("已忽略") {
                Button("取消忽略") {
                    Task { await viewModel.removeFromIgnoreList(workingCopy: workingCopy, paths: [entry.path]) }
                }
            }
        }
        if entry.isCommittable || entry.itemStatus == .conflicted {
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

    private func openDiff(for path: String) {
        if appSettings.preferExternalDiff && appSettings.hasExternalDiffTool {
            Task { await openExternalDiff(path: path) }
        } else {
            diffPath = path
        }
    }

    private func openExternalDiff(path: String) async {
        do {
            try await ExternalDiffService.open(
                kind: .workingCopy(path: path),
                workingCopy: workingCopy,
                settings: appSettings,
                authStore: authStore
            )
        } catch {
            externalDiffError = error.localizedDescription
        }
    }

    private func startFileWatcherIfNeeded() {
        fileWatcher.stop()
        guard authStore.autoRefreshEnabled else { return }
        fileWatcher.watch(path: workingCopy.path) { [viewModel] changedPaths in
            guard !viewModel.shouldSkipWatcherRefresh else { return }
            viewModel.requestRefresh(
                workingCopy: workingCopy,
                changedPaths: changedPaths.isEmpty ? nil : changedPaths
            )
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
                viewModel.requestRefresh(workingCopy: workingCopy)
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
                return (entry.statusSymbolName, entry.statusColor, entry.statusDisplayName)
            }
            let status = node.representativeStatus
            return (
                "folder.fill",
                status?.color ?? .secondary,
                count > 1 ? "\(count) 项" : (status?.displayName ?? "目录")
            )
        }
        if let entry = node.entry {
            let label = entry.isTreeConflicted && entry.itemStatus != .conflicted
                ? "树冲突"
                : entry.statusDisplayName
            return (entry.statusSymbolName, entry.statusColor, label)
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

/// 可滚动的操作提示面板，避免长文本 alert 卡死界面。
private struct OperationNoticeSheet: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.top, 16)
                .padding(.horizontal, 20)

            ScrollView {
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("好") {
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 320)
    }
}
