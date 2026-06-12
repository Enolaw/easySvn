import SwiftUI
import SvnKit

/// 创建分支/标签面板（svn copy）。
struct BranchTagSheet: View {
    let workingCopy: WorkingCopy
    @ObservedObject var viewModel: BranchTagViewModel
    let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("创建分支 / 标签")
                .font(.headline)

            Picker("类型", selection: $viewModel.kind) {
                ForEach(RepositoryCopyKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            labeledField("来源 URL", text: $viewModel.sourceURL)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(viewModel.kind.displayName)名称")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("feature-x", text: $viewModel.name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.name) { _ in
                        viewModel.applySuggestedName()
                    }
            }

            if !viewModel.destinationURL.isEmpty {
                Text("目标：\(viewModel.destinationURL.displayDecodedURL)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            labeledField("提交日志", text: $viewModel.message)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task {
                        if await viewModel.create(workingCopy: workingCopy) {
                            await onComplete()
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("创建")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmit)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            await viewModel.load(workingCopy: workingCopy)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
