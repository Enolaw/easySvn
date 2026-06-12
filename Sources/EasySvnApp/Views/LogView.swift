import SwiftUI
import SvnKit

/// 提交日志查看器。
struct LogView: View {
    let workingCopy: WorkingCopy

    @EnvironmentObject private var authStore: AuthSettingsStore
    @EnvironmentObject private var appSettings: AppSettingsStore
    @StateObject private var viewModel = LogViewModel()
    @State private var diffPresentation: DiffPresentation?
    @State private var externalDiffError: String?

    private struct DiffPresentation: Identifiable {
        let id = UUID()
        let revision: Int
        let path: String
        let action: SvnChangeAction?
    }

    var body: some View {
        HSplitView {
            revisionList
                .frame(minWidth: 260, idealWidth: 300)
            revisionDetail
                .frame(minWidth: 320)
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索作者、版本号或日志")
        .toolbar { toolbarContent }
        .task(id: workingCopy.id) {
            viewModel.configure(authStore: authStore)
            await viewModel.load(workingCopy: workingCopy)
        }
        .alert("无法打开外部工具", isPresented: Binding(
            get: { externalDiffError != nil },
            set: { if !$0 { externalDiffError = nil } }
        )) {
            Button("好") { externalDiffError = nil }
        } message: {
            Text(externalDiffError ?? "")
        }
        .sheet(item: $diffPresentation) { item in
            DiffView(
                workingCopy: workingCopy,
                source: .revision(revision: item.revision, path: item.path, action: item.action),
                title: "r\(item.revision) · \(item.path)"
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await viewModel.load(workingCopy: workingCopy, forceRefresh: true) }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
        if viewModel.isServingFromCache {
            ToolbarItem(placement: .automatic) {
                Text("缓存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var revisionList: some View {
        Group {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView("正在加载日志…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.entries.isEmpty {
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $viewModel.selectedRevision) {
                    ForEach(viewModel.filteredEntries, id: \.revision) { entry in
                        LogRevisionRow(entry: entry)
                            .tag(entry.revision)
                            .contextMenu {
                                Button("复制版本号") {
                                    viewModel.copyRevision(entry.revision)
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .safeAreaInset(edge: .bottom) {
                    if viewModel.hasMore {
                        HStack {
                            Spacer()
                            Button {
                                Task { await viewModel.loadMore(workingCopy: workingCopy) }
                            } label: {
                                if viewModel.isLoadingMore {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("加载更早的版本")
                                }
                            }
                            .disabled(viewModel.isLoadingMore)
                            Spacer()
                        }
                        .padding(8)
                        .background(.bar)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var revisionDetail: some View {
        if let entry = viewModel.selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("r\(entry.revision)")
                            .font(.title2.weight(.semibold).monospacedDigit())
                        if let author = entry.author {
                            Text(author)
                                .foregroundStyle(.secondary)
                        }
                        if let date = entry.date {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                        Button("复制版本号") {
                            viewModel.copyRevision(entry.revision)
                        }
                    }

                    Text(entry.message.isEmpty ? "（无提交说明）" : entry.message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    if !entry.changedPaths.isEmpty {
                        Divider()
                        Text("变更文件（\(entry.changedPaths.count)）")
                            .font(.headline)
                        ForEach(entry.changedPaths, id: \.path) { changed in
                            Button {
                                openDiff(revision: entry.revision, path: changed.path, action: changed.action)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(changed.action.rawValue)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(actionColor(changed.action))
                                        .frame(width: 16)
                                    Text(changed.path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("查看差异") {
                                    openDiff(revision: entry.revision, path: changed.path, action: changed.action)
                                }
                                if appSettings.hasExternalDiffTool {
                                    Button("使用外部工具查看差异") {
                                        Task {
                                            await openExternalDiff(
                                                revision: entry.revision,
                                                path: changed.path,
                                                action: changed.action
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("选择一条日志")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func openDiff(revision: Int, path: String, action: SvnChangeAction) {
        if appSettings.preferExternalDiff && appSettings.hasExternalDiffTool {
            Task { await openExternalDiff(revision: revision, path: path, action: action) }
        } else {
            diffPresentation = DiffPresentation(revision: revision, path: path, action: action)
        }
    }

    private func openExternalDiff(revision: Int, path: String, action: SvnChangeAction) async {
        do {
            try await ExternalDiffService.open(
                kind: .revision(revision: revision, path: path, action: action),
                workingCopy: workingCopy,
                settings: appSettings,
                authStore: authStore
            )
        } catch {
            externalDiffError = error.localizedDescription
        }
    }

    private func actionColor(_ action: SvnChangeAction) -> Color {
        switch action {
        case .added: .green
        case .modified: .blue
        case .deleted: .red
        case .replaced: .purple
        }
    }
}

private struct LogRevisionRow: View {
    let entry: SvnLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("r\(entry.revision)")
                    .font(.body.weight(.semibold).monospacedDigit())
                if let author = entry.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let date = entry.date {
                    Text(date.formatted(date: .numeric, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(entry.message.isEmpty ? "（无提交说明）" : entry.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}
