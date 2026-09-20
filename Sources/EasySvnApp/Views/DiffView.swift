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
    @State private var currentChangeIndex = 0
    @State private var wrapLines = true

    private let diffFontSize: CGFloat = 12
    private var diffFont: Font { .system(size: diffFontSize, design: .monospaced) }

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
            .onChange(of: viewModel.textLayout) { _ in
                currentChangeIndex = 0
            }
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(
            MacResizableWindow(
                minSize: NSSize(width: 720, height: 420),
                idealSize: NSSize(width: 1180, height: 760)
            )
            .allowsHitTesting(false)
        )
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
            changeNavigator(blockIDs: viewModel.changeBlockIDs)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.sideBySideRows) { row in
                            Group {
                                if row.isHunkHeader {
                                    hunkHeaderRow(row.hunkLabel ?? "")
                                } else {
                                    sideBySideRow(row)
                                }
                            }
                            .id(row.id)
                            .overlay(alignment: .leading) {
                                if row.id == targetID(in: viewModel.changeBlockIDs) {
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(width: 3)
                                }
                            }
                        }
                    }
                }
                .onAppear { scrollToCurrentChange(proxy: proxy, ids: viewModel.changeBlockIDs) }
                .onChange(of: currentChangeIndex) { _ in
                    scrollToCurrentChange(proxy: proxy, ids: viewModel.changeBlockIDs)
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

    private func changeNavigator(blockIDs: [Int]) -> some View {
        HStack(spacing: 10) {
            Text("−\(viewModel.deletedLineCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.red)
            Text("+\(viewModel.addedLineCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.green)

            Divider().frame(height: 12)

            if blockIDs.isEmpty {
                Text("没有可跳转的变更块")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("变更 \(min(currentChangeIndex + 1, blockIDs.count)) / \(blockIDs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("上一处") {
                    currentChangeIndex = max(0, currentChangeIndex - 1)
                }
                .disabled(currentChangeIndex <= 0)
                .keyboardShortcut(.upArrow, modifiers: [.option])
                .help("上一处变更（⌥↑）")

                Button("下一处") {
                    currentChangeIndex = min(blockIDs.count - 1, currentChangeIndex + 1)
                }
                .disabled(currentChangeIndex >= blockIDs.count - 1)
                .keyboardShortcut(.downArrow, modifiers: [.option])
                .help("下一处变更（⌥↓）")
            }

            Spacer()
            Toggle("自动换行", isOn: $wrapLines)
                .toggleStyle(.checkbox)
                .help("按栏宽换行。关闭后该栏内横向滚动，左右两栏始终同时可见")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func hunkHeaderRow(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.08))
    }

    private func sideBySideRow(_ row: SideBySideRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            textCell(
                lineNumber: row.leftLineNumber,
                text: row.leftText,
                highlight: row.leftHighlight,
                inlineRanges: row.leftInlineRanges
            )
            Divider()
            textCell(
                lineNumber: row.rightLineNumber,
                text: row.rightText,
                highlight: row.rightHighlight,
                inlineRanges: row.rightInlineRanges
            )
        }
    }

    private func textCell(
        lineNumber: Int?,
        text: String?,
        highlight: SideBySideHighlight,
        inlineRanges: [InlineHighlightRange]
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(lineNumber.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
            Text(gutterMarker(for: highlight))
                .font(.system(size: 11, design: .monospaced).weight(.semibold))
                .foregroundStyle(gutterColor(for: highlight))
                .frame(width: 10, alignment: .center)
            cellText(
                attributedLine(
                    text: text ?? "",
                    highlight: highlight,
                    inlineRanges: inlineRanges
                )
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(backgroundColor(for: highlight))
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .topLeading)
    }

    @ViewBuilder
    private func cellText(_ attributed: AttributedString) -> some View {
        if wrapLines {
            Text(attributed)
                .font(diffFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(attributed)
                    .font(diffFont)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unifiedDiffContent: some View {
        VStack(spacing: 0) {
            changeNavigator(blockIDs: viewModel.unifiedChangeBlockIDs)
            Divider()
            ScrollViewReader { proxy in
                ScrollView(wrapLines ? [.vertical] : [.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.lines) { line in
                            if line.kind != .header {
                                unifiedLine(line)
                                    .id(line.id)
                                    .overlay(alignment: .leading) {
                                        if line.id == targetID(in: viewModel.unifiedChangeBlockIDs) {
                                            Rectangle()
                                                .fill(Color.accentColor)
                                                .frame(width: 3)
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: wrapLines ? .infinity : nil, alignment: .topLeading)
                }
                .onAppear { scrollToCurrentChange(proxy: proxy, ids: viewModel.unifiedChangeBlockIDs) }
                .onChange(of: currentChangeIndex) { _ in
                    scrollToCurrentChange(proxy: proxy, ids: viewModel.unifiedChangeBlockIDs)
                }
            }
        }
    }

    private func unifiedLine(_ line: DiffLine) -> some View {
        Group {
            if line.kind == .hunk {
                hunkHeaderRow(SideBySideDiffBuilder.hunkDisplayLabel(line.text))
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Text(unifiedMarker(for: line.kind))
                        .font(.system(size: 11, design: .monospaced).weight(.semibold))
                        .foregroundStyle(unifiedForegroundColor(for: line.kind))
                        .frame(width: 10, alignment: .center)
                    Text(unifiedDisplayText(line))
                        .font(diffFont)
                        .foregroundStyle(unifiedForegroundColor(for: line.kind))
                        .lineLimit(wrapLines ? nil : 1)
                        .fixedSize(horizontal: !wrapLines, vertical: false)
                        .frame(maxWidth: wrapLines ? .infinity : nil, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 1)
                .background(unifiedBackgroundColor(for: line.kind))
            }
        }
    }

    private func attributedLine(
        text: String,
        highlight: SideBySideHighlight,
        inlineRanges: [InlineHighlightRange]
    ) -> AttributedString {
        let display = text.isEmpty ? " " : text
        var result = AttributedString(display)
        result.font = diffFont
        result.foregroundColor = foregroundColor(for: highlight)

        guard !text.isEmpty else { return result }

        for range in inlineRanges {
            guard let stringRange = InlineDiffHighlighter.characterRange(
                in: text,
                start: range.start,
                length: range.length
            ), let attributedRange = Range(stringRange, in: result) else {
                continue
            }
            result[attributedRange].backgroundColor = inlineBackgroundColor(for: highlight)
            result[attributedRange].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }

    private func gutterMarker(for highlight: SideBySideHighlight) -> String {
        switch highlight {
        case .deletion: "−"
        case .addition: "+"
        case .context, .empty: " "
        }
    }

    private func gutterColor(for highlight: SideBySideHighlight) -> Color {
        switch highlight {
        case .deletion: .red
        case .addition: .green
        case .context, .empty: .clear
        }
    }

    private func foregroundColor(for highlight: SideBySideHighlight) -> Color {
        switch highlight {
        case .deletion: Color.red.opacity(0.95)
        case .addition: Color.green.opacity(0.95)
        case .context: .primary
        case .empty: .clear
        }
    }

    private func backgroundColor(for highlight: SideBySideHighlight) -> Color {
        switch highlight {
        case .deletion: Color.red.opacity(0.10)
        case .addition: Color.green.opacity(0.10)
        case .context: .clear
        case .empty: Color.secondary.opacity(0.05)
        }
    }

    private func inlineBackgroundColor(for highlight: SideBySideHighlight) -> Color {
        switch highlight {
        case .deletion: Color.red.opacity(0.32)
        case .addition: Color.green.opacity(0.32)
        default: .clear
        }
    }

    private func unifiedDisplayText(_ line: DiffLine) -> String {
        let raw = line.text
        if line.kind == .addition || line.kind == .deletion || line.kind == .context {
            return raw.isEmpty ? " " : String(raw.dropFirst())
        }
        return raw.isEmpty ? " " : raw
    }

    private func unifiedMarker(for kind: DiffLineKind) -> String {
        switch kind {
        case .addition: "+"
        case .deletion: "−"
        default: " "
        }
    }

    private func unifiedForegroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: Color.green.opacity(0.95)
        case .deletion: Color.red.opacity(0.95)
        case .hunk: .secondary
        case .header: .secondary
        case .context: .primary
        }
    }

    private func unifiedBackgroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: Color.green.opacity(0.10)
        case .deletion: Color.red.opacity(0.10)
        case .hunk: Color.blue.opacity(0.08)
        default: .clear
        }
    }

    private func targetID(in ids: [Int]) -> Int? {
        guard !ids.isEmpty else { return nil }
        let clamped = min(max(currentChangeIndex, 0), ids.count - 1)
        return ids[clamped]
    }

    private func scrollToCurrentChange(proxy: ScrollViewProxy, ids: [Int]) {
        guard !ids.isEmpty else { return }
        let clamped = min(max(currentChangeIndex, 0), ids.count - 1)
        let target = ids[clamped]
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.15)) {
                proxy.scrollTo(target, anchor: .center)
            }
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
