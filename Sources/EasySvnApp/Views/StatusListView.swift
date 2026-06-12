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

    var body: some View {
        Group {
            if let message = viewModel.errorMessage {
                errorView(message)
            } else {
                VStack(spacing: 0) {
                    infoHeader
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
                fileCount: viewModel.selectedPaths.count,
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
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
            .disabled(viewModel.isLoading || viewModel.selectedPaths.isEmpty)

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

    // MARK: - 信息头

    private var infoHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                if let info = viewModel.info {
                    Text(info.url)
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

    private func lastCommitText(_ info: SvnInfo) -> String {
        guard let revision = info.lastCommitRevision else { return "" }
        var text = " · 最后提交 r\(revision)"
        if let author = info.lastCommitAuthor {
            text += " by \(author)"
        }
        return text
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
            List(viewModel.entries, id: \.path) { entry in
                StatusRow(
                    entry: entry,
                    isSelected: StatusViewModel.isCommittable(entry.itemStatus)
                        ? selectionBinding(for: entry.path)
                        : nil
                )
                .contextMenu { rowMenu(for: entry) }
            }
            .listStyle(.inset)
        }
    }

    private func selectionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedPaths.contains(path) },
            set: { isOn in
                if isOn {
                    viewModel.selectedPaths.insert(path)
                } else {
                    viewModel.selectedPaths.remove(path)
                }
            }
        )
    }

    @ViewBuilder
    private func rowMenu(for entry: SvnStatusEntry) -> some View {
        if entry.itemStatus == .unversioned {
            Button("加入版本控制") {
                Task { await viewModel.addToVersionControl(workingCopy: workingCopy, paths: [entry.path]) }
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
            NSWorkspace.shared.activateFileViewerSelecting([url])
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

/// 单条变更文件行（可提交项带勾选框）。
struct StatusRow: View {
    let entry: SvnStatusEntry
    let isSelected: Binding<Bool>?

    var body: some View {
        HStack(spacing: 10) {
            if let isSelected {
                Toggle("", isOn: isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            } else {
                Spacer().frame(width: 16)
            }
            Image(systemName: entry.itemStatus.symbolName)
                .foregroundStyle(entry.itemStatus.color)
                .frame(width: 18)
            Text(entry.path)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(entry.itemStatus.displayName)
                .font(.caption)
                .foregroundStyle(entry.itemStatus.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(entry.itemStatus.color.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 1)
    }
}
