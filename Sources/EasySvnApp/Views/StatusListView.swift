import SwiftUI
import SvnKit

/// 选中工作副本的状态视图：信息头 + 变更文件列表。
struct StatusListView: View {
    let workingCopy: WorkingCopy

    @StateObject private var viewModel = StatusViewModel()

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refresh(workingCopy: workingCopy) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.isLoading)
            }
        }
        .task(id: workingCopy.id) {
            await viewModel.refresh(workingCopy: workingCopy)
        }
    }

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
                StatusRow(entry: entry)
            }
            .listStyle(.inset)
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

/// 单条变更文件行。
struct StatusRow: View {
    let entry: SvnStatusEntry

    var body: some View {
        HStack(spacing: 10) {
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
