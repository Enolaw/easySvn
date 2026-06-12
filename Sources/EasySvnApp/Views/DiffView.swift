import SwiftUI

/// 统一 diff 文本视图（语法高亮）。
struct DiffView: View {
    let workingCopy: WorkingCopy
    @StateObject private var viewModel: DiffViewModel
    @Environment(\.dismiss) private var dismiss

    init(workingCopy: WorkingCopy, source: DiffViewModel.Source, title: String) {
        self.workingCopy = workingCopy
        _viewModel = StateObject(wrappedValue: DiffViewModel(source: source, title: title))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("正在加载差异…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if viewModel.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("没有差异")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    diffContent
                }
            }
            .navigationTitle(viewModel.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                await viewModel.load(workingCopy: workingCopy)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
    }

    private var diffContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(foregroundColor(for: line.kind))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 1)
                        .background(backgroundColor(for: line.kind))
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func foregroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        case .hunk: .blue
        case .header: .secondary
        case .context: .primary
        }
    }

    private func backgroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: Color.green.opacity(0.12)
        case .deletion: Color.red.opacity(0.12)
        case .hunk: Color.blue.opacity(0.08)
        default: .clear
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
