import AppKit
import SwiftUI
import SvnKit

private enum RepoBrowserSheet: Identifiable {
    case newFolder
    case delete
    case rename
    case checkout

    var id: String {
        switch self {
        case .newFolder: "newFolder"
        case .delete: "delete"
        case .rename: "rename"
        case .checkout: "checkout"
        }
    }
}

private struct RemoteLogPresentation: Identifiable {
    let id = UUID()
    let url: String
    let fileName: String
}

/// 仓库浏览器：远程目录树、CRUD、文件预览、从此处检出。
struct RepoBrowserView: View {
    let workingCopy: WorkingCopy
    let onCheckoutComplete: (URL) -> Void

    @EnvironmentObject private var authStore: AuthSettingsStore
    @StateObject private var viewModel = RepoBrowserViewModel()
    @StateObject private var checkoutViewModel = CheckoutViewModel()
    @State private var activeSheet: RepoBrowserSheet?
    @State private var logPresentation: RemoteLogPresentation?

    var body: some View {
        VStack(spacing: 0) {
            if let message = viewModel.operationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.08))
            }

            HSplitView {
                RepoBrowserTreeView(viewModel: viewModel, onViewLog: showLog)
                    .frame(minWidth: 200, idealWidth: 240)
                    .background(AppSurfaceColors.sidebar)

                detailPanel
                    .frame(minWidth: 360)
                    .background(AppSurfaceColors.repoDirectory)
            }
        }
        .toolbar { toolbarContent }
        .task(id: workingCopy.id) {
            viewModel.configure(authStore: authStore)
            await viewModel.load(workingCopy: workingCopy)
        }
        .sheet(item: $logPresentation) { item in
            RemoteFileLogSheet(
                fileURL: item.url,
                fileName: item.fileName,
                workingCopy: workingCopy
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newFolder:
                NewRemoteFolderSheet { name, message in
                    await viewModel.createFolder(name: name, message: message, workingCopy: workingCopy)
                }
            case .delete:
                if let url = viewModel.selectedURL {
                    RemoteMessageSheet(
                        title: "删除远程路径",
                        prompt: RepositoryURLHelper.lastComponent(of: url),
                        confirmLabel: "删除",
                        isDestructive: true
                    ) { message in
                        await viewModel.deleteSelected(message: message, workingCopy: workingCopy)
                    }
                }
            case .rename:
                if let url = viewModel.selectedURL {
                    RenameRemoteSheet(currentName: RepositoryURLHelper.lastComponent(of: url)) { name, message in
                        await viewModel.renameSelected(to: name, message: message, workingCopy: workingCopy)
                    }
                }
            case .checkout:
                CheckoutSheet(viewModel: checkoutViewModel) { url in
                    onCheckoutComplete(url)
                }
                .onAppear {
                    checkoutViewModel.configure(authStore: authStore)
                    if let url = viewModel.selectedURL, viewModel.selectedIsDirectory {
                        checkoutViewModel.repositoryURL = RepositoryURLHelper.displayDecoded(url)
                    }
                }
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("好") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Toggle("指定版本", isOn: $viewModel.useRevision)
        }
        ToolbarItem(placement: .automatic) {
            if viewModel.useRevision {
                TextField("HEAD", text: $viewModel.revision)
                    .frame(width: 80)
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                viewModel.goUpDeferred()
            } label: {
                Label("上一级", systemImage: "chevron.left")
            }
            .disabled(!viewModel.canGoUp)
            .help("返回上一级文件夹")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if let url = viewModel.selectedURL, !viewModel.selectedIsDirectory {
                Button {
                    exportFile(url)
                } label: {
                    Label("导出", systemImage: "square.and.arrow.down")
                }
            }

            Button {
                activeSheet = .newFolder
            } label: {
                Label("新建目录", systemImage: "folder.badge.plus")
            }
            .disabled(viewModel.selectedURL == nil)

            Button {
                activeSheet = .checkout
            } label: {
                Label("检出", systemImage: "arrow.down.doc")
            }
            .disabled(viewModel.selectedURL == nil || !viewModel.selectedIsDirectory)
        }
    }

    private var detailPanel: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            if !viewModel.selectedIsDirectory, viewModel.selectedURL != nil {
                filePreview
            } else {
                directoryList
            }
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.goUpDeferred()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.canGoUp)
            .help("返回上一级文件夹")

            if let name = viewModel.selectedFileName {
                Image(systemName: "doc.text")
                    .foregroundStyle(.blue)
                Text(name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("文件预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(.blue)
                Text(RepositoryURLHelper.lastComponent(of: viewModel.currentURL))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("单击文件查看内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppSurfaceColors.chromeBar)
    }

    private var directoryList: some View {
        Group {
            if viewModel.isLoading, viewModel.listItems.isEmpty {
                ProgressView("正在加载…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.listItems.isEmpty {
                Text("空目录")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.listItems, selection: Binding(
                    get: { viewModel.selectedURL },
                    set: { newValue in
                        guard let newValue else { return }
                        viewModel.selectDeferred(newValue)
                    }
                )) { item in
                    HStack {
                        Image(systemName: item.kind == .dir ? "folder.fill" : "doc.fill")
                            .foregroundStyle(item.kind == .dir ? .blue : .secondary)
                        Text(item.name)
                        Spacer()
                        if item.kind == .file {
                            Text("查看")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let date = item.commitDate {
                            Text(date.formatted(date: .numeric, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let rev = item.commitRevision {
                            Text("r\(rev)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(item.url)
                    .contextMenu { itemMenu(for: item) }
                    .onTapGesture(count: 2) {
                        if item.kind == .dir {
                            viewModel.selectDeferred(item.url)
                        } else {
                            viewModel.selectDeferred(item.url)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppSurfaceColors.repoDirectory)
    }

    private var filePreview: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("文件内容")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                Group {
                    if viewModel.isLoadingPreview {
                        ProgressView("正在加载文件…")
                    } else if let content = viewModel.fileContent {
                        ScrollView {
                            Text(content)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    } else {
                        Text("无法预览")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 200)
            .background(AppSurfaceColors.repoDirectory)

            logSection
                .frame(minHeight: 140)
        }
        .background(AppSurfaceColors.repoDirectory)
        .contextMenu {
            if let url = viewModel.selectedURL {
                itemMenu(for: RepoTreeNode(
                    entry: SvnListEntry(name: RepositoryURLHelper.lastComponent(of: url), kind: .file),
                    parentURL: RepositoryURLHelper.parentURL(of: url) ?? viewModel.rootURL
                ))
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("提交日志")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            if viewModel.logEntries.isEmpty {
                Text("无日志")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
            } else {
                List(viewModel.logEntries, id: \.revision) { entry in
                    HStack {
                        Text("r\(entry.revision)")
                            .font(.caption.monospacedDigit())
                        if let author = entry.author {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppSurfaceColors.repoDirectory)
    }

    @ViewBuilder
    private func itemMenu(for item: RepoTreeNode) -> some View {
        Button("复制远程链接") {
            viewModel.copyRemoteURL(item.url)
        }
        Divider()
        if item.kind == .dir {
            Button("打开") {
                viewModel.selectDeferred(item.url)
            }
            Button("查看日志…") {
                showLog(for: item)
            }
            Button("从此处检出…") {
                checkoutViewModel.repositoryURL = RepositoryURLHelper.displayDecoded(item.url)
                activeSheet = .checkout
            }
            Button("新建子目录…") {
                Task {
                    await viewModel.select(item.url)
                    activeSheet = .newFolder
                }
            }
        } else {
            Button("查看内容") {
                viewModel.selectDeferred(item.url)
            }
            Button("查看日志…") {
                showLog(for: item)
            }
            Button("导出到本地…") {
                exportFile(item.url)
            }
        }
        if item.url != viewModel.rootURL {
            Button("重命名…") {
                viewModel.selectDeferred(item.url)
                activeSheet = .rename
            }
            Button("删除…", role: .destructive) {
                viewModel.selectDeferred(item.url)
                activeSheet = .delete
            }
        }
    }

    private func showLog(for item: RepoTreeNode) {
        logPresentation = RemoteLogPresentation(url: item.url, fileName: item.name)
    }

    private func exportFile(_ url: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = RepositoryURLHelper.lastComponent(of: url)
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Task {
            let succeeded = await viewModel.exportSelected(
                url: url,
                to: dest,
                workingCopy: workingCopy
            )
            if succeeded {
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            }
        }
    }
}
