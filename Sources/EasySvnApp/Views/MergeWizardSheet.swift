import SwiftUI

/// 合并向导：dry-run 预览、执行合并、mergeinfo 展示。
struct MergeWizardSheet: View {
    let workingCopy: WorkingCopy
    @ObservedObject var viewModel: MergeWizardViewModel
    let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("合并")
                .font(.headline)

            Picker("模式", selection: $viewModel.mode) {
                ForEach(MergeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("来源 URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("分支或路径 URL", text: $viewModel.sourceURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.sourceURL) { _ in
                        Task { await viewModel.refreshMergeinfo(workingCopy: workingCopy) }
                    }
            }

            if viewModel.mode == .revisionRange {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("起始版本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("100", text: $viewModel.revisionFrom)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    Text(":")
                        .padding(.top, 18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("结束版本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("HEAD", text: $viewModel.revisionTo)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }
            }

            mergeinfoSection

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("预览（dry-run）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新预览") {
                        Task { await viewModel.dryRun(workingCopy: workingCopy) }
                    }
                    .disabled(!viewModel.canMerge || viewModel.isWorking)
                }
                ScrollView {
                    Text(viewModel.dryRunResult.isEmpty ? "点击「刷新预览」查看合并影响" : viewModel.dryRunResult)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(height: 120)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(error.contains("冲突") ? .orange : .red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task {
                        if await viewModel.merge(workingCopy: workingCopy) {
                            await onComplete()
                            if viewModel.errorMessage == nil {
                                dismiss()
                            }
                        }
                    }
                } label: {
                    if viewModel.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("执行合并")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canMerge)
            }
        }
        .padding(20)
        .frame(width: 540, height: 520)
        .task {
            await viewModel.load(workingCopy: workingCopy)
        }
    }

    private var mergeinfoSection: some View {
        HStack(alignment: .top, spacing: 16) {
            mergeinfoColumn("已合并", revisions: viewModel.mergedRevisions)
            mergeinfoColumn("可合并", revisions: viewModel.eligibleRevisions)
        }
    }

    private func mergeinfoColumn(_ title: String, revisions: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title)（\(revisions.count)）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(revisions.isEmpty ? "无" : revisions.map { "r\($0)" }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
