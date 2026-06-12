import AppKit
import SwiftUI

/// Diff 视图：图片左右并排预览，文本支持并排 / 统一 diff。
struct DiffView: View {
    let workingCopy: WorkingCopy
    @EnvironmentObject private var authStore: AuthSettingsStore
    @EnvironmentObject private var appSettings: AppSettingsStore
    @StateObject private var viewModel: DiffViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var externalDiffError: String?

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
                    emptyView
                } else if viewModel.contentKind == .image {
                    imageDiffContent
                } else if viewModel.textLayout == .sideBySide {
                    textSideBySideContent
                } else {
                    unifiedDiffContent
                }
            }
            .navigationTitle(viewModel.title)
            .toolbar { toolbarContent }
            .alert("无法打开外部工具", isPresented: Binding(
                get: { externalDiffError != nil },
                set: { if !$0 { externalDiffError = nil } }
            )) {
                Button("好") { externalDiffError = nil }
            } message: {
                Text(externalDiffError ?? "")
            }
            .task {
                viewModel.configure(authStore: authStore)
                await viewModel.load(workingCopy: workingCopy)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { dismiss() }
        }
        if viewModel.contentKind == .text && !viewModel.isEmpty {
            ToolbarItem(placement: .principal) {
                Picker("显示", selection: $viewModel.textLayout) {
                    ForEach(DiffTextLayout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
        if appSettings.hasExternalDiffTool {
            ToolbarItem(placement: .primaryAction) {
                Button("外部工具") {
                    Task { await openExternalDiff() }
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("没有差异")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var imageDiffContent: some View {
        HSplitView {
            imagePane(
                label: viewModel.leftLabel,
                data: viewModel.leftImageData,
                placeholder: "（无旧版本）"
            )
            imagePane(
                label: viewModel.rightLabel,
                data: viewModel.rightImageData,
                placeholder: "（无新版本）"
            )
        }
    }

    private func imagePane(label: String, data: Data?, placeholder: String) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            Divider()
            Group {
                if let data, let image = NSImage(data: data) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(12)
                    }
                } else {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 280)
    }

    private var textSideBySideContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                columnHeader("旧版本", subtitle: viewModel.leftLabel)
                Divider()
                columnHeader("新版本", subtitle: viewModel.rightLabel)
            }
            .background(.bar)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.sideBySideRows) { row in
                        sideBySideRow(row)
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private func columnHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sideBySideRow(_ row: SideBySideRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            textCell(
                lineNumber: row.leftLineNumber,
                text: row.leftText,
                highlight: row.leftHighlight
            )
            Divider()
            textCell(
                lineNumber: row.rightLineNumber,
                text: row.rightText,
                highlight: row.rightHighlight
            )
        }
    }

    private func textCell(
        lineNumber: Int?,
        text: String?,
        highlight: SideBySideHighlight
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(lineNumber.map(String.init) ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
            Text(text ?? "")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(foregroundColor(for: highlight))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(backgroundColor(for: highlight))
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
    }

    private var unifiedDiffContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(unifiedForegroundColor(for: line.kind))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 1)
                        .background(unifiedBackgroundColor(for: line.kind))
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func foregroundColor(for highlight: SideBySideHighlight) -> Color {
        switch highlight {
        case .deletion: .red
        case .addition: .green
        case .context: .primary
        case .empty: .clear
        }
    }

    private func backgroundColor(for highlight: SideBySideHighlight) -> Color {
        switch highlight {
        case .deletion: Color.red.opacity(0.12)
        case .addition: Color.green.opacity(0.12)
        case .context: .clear
        case .empty: Color.secondary.opacity(0.04)
        }
    }

    private func unifiedForegroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        case .hunk: .blue
        case .header: .secondary
        case .context: .primary
        }
    }

    private func unifiedBackgroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: Color.green.opacity(0.12)
        case .deletion: Color.red.opacity(0.12)
        case .hunk: Color.blue.opacity(0.08)
        default: .clear
        }
    }

    private func openExternalDiff() async {
        do {
            try await ExternalDiffService.open(
                kind: externalDiffKind,
                workingCopy: workingCopy,
                settings: appSettings,
                authStore: authStore
            )
        } catch {
            externalDiffError = error.localizedDescription
        }
    }

    private var externalDiffKind: ExternalDiffKind {
        switch viewModel.source {
        case .workingCopy(let path):
            return .workingCopy(path: path)
        case .revision(let revision, let path, let action):
            return .revision(revision: revision, path: path, action: action)
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
