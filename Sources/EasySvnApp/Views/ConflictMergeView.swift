import SwiftUI
import SvnKit

/// 冲突三方合并视图：mine / base / theirs + 可编辑结果区。
struct ConflictMergeView: View {
    let workingCopy: WorkingCopy
    let path: String
    let isTreeConflict: Bool
    let onResolved: () async -> Void

    @EnvironmentObject private var authStore: AuthSettingsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ConflictMergeViewModel

    init(
        workingCopy: WorkingCopy,
        path: String,
        isTreeConflict: Bool,
        onResolved: @escaping () async -> Void
    ) {
        self.workingCopy = workingCopy
        self.path = path
        self.isTreeConflict = isTreeConflict
        self.onResolved = onResolved
        _viewModel = StateObject(wrappedValue: ConflictMergeViewModel(path: path, isTreeConflict: isTreeConflict))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading, viewModel.versions.working == nil, viewModel.treeConflict == nil {
                    ProgressView("正在加载冲突…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if isTreeConflict, !viewModel.versions.hasTextConflict {
                    treeConflictContent
                } else {
                    textMergeContent
                }
            }
            .navigationTitle(path)
            .toolbar { toolbarContent }
            .task {
                viewModel.configure(authStore: authStore)
                await viewModel.load(workingCopy: workingCopy)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { dismiss() }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("采用我的") {
                Task { await quickResolve(.mineFull) }
            }
            .disabled(viewModel.isLoading)

            Button("采用对方") {
                Task { await quickResolve(.theirsFull) }
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var textMergeContent: some View {
        VStack(spacing: 0) {
            if !viewModel.hunks.isEmpty {
                hunkNavigator
                Divider()
            }
            HSplitView {
                conflictColumn("我的", text: viewModel.versions.mine, tint: .blue)
                conflictColumn("BASE", text: viewModel.versions.base, tint: .secondary)
                conflictColumn("对方", text: viewModel.versions.theirs, tint: .orange)
            }
            .frame(minHeight: 200)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("合并结果")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                TextEditor(text: $viewModel.resultText)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
            }
            .frame(minHeight: 160)
            if let message = viewModel.operationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(8)
            }
            HStack {
                Spacer()
                Button("保存并标记已解决") {
                    Task {
                        if await viewModel.saveAndResolve(workingCopy: workingCopy) {
                            await onResolved()
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
            }
            .padding(12)
        }
    }

    private var treeConflictContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("树冲突", systemImage: "folder.badge.questionmark")
                .font(.headline)
                .foregroundStyle(.orange)

            if let conflict = viewModel.treeConflict {
                VStack(alignment: .leading, spacing: 8) {
                    Text("操作")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(conflict.operation)
                        .font(.body)
                    if let left = conflict.sourceLeft {
                        Text("左侧：\(left)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let right = conflict.sourceRight {
                        Text("右侧：\(right)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("无法读取树冲突详情，请尝试快捷解决。")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("采用我的") {
                    Task { await quickResolve(.mineFull) }
                }
                Button("采用对方") {
                    Task { await quickResolve(.theirsFull) }
                }
                Spacer()
                Button("标记已解决") {
                    Task { await quickResolve(.working) }
                }
            }
            .disabled(viewModel.isLoading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var hunkNavigator: some View {
        HStack(spacing: 12) {
            Text("冲突块 \(viewModel.hunks.isEmpty ? 0 : viewModel.currentHunkIndex + 1) / \(viewModel.hunks.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("上一块") {
                viewModel.currentHunkIndex = max(0, viewModel.currentHunkIndex - 1)
            }
            .disabled(viewModel.currentHunkIndex <= 0)
            Button("下一块") {
                viewModel.currentHunkIndex = min(viewModel.hunks.count - 1, viewModel.currentHunkIndex + 1)
            }
            .disabled(viewModel.currentHunkIndex >= viewModel.hunks.count - 1)
            Button("此块·我的") { viewModel.chooseMineForCurrentHunk() }
            Button("此块·对方") { viewModel.chooseTheirsForCurrentHunk() }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func conflictColumn(_ title: String, text: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            ScrollView {
                Text(text ?? "（无）")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }
        }
    }

    private func quickResolve(_ accept: SvnResolveAccept) async {
        if await viewModel.resolve(workingCopy: workingCopy, accept: accept) {
            await onResolved()
            dismiss()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("重试") {
                Task { await viewModel.load(workingCopy: workingCopy) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
