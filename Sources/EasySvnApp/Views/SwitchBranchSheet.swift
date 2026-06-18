import SwiftUI
import SvnKit

/// 切换分支面板（svn switch）。
struct SwitchBranchSheet: View {
    let workingCopy: WorkingCopy
    @ObservedObject var viewModel: SwitchBranchViewModel
    let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("切换分支")
                .font(.headline)

            if !viewModel.currentURL.isEmpty {
                Text("当前：\(viewModel.currentURL)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("目标 URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://svn.example.com/repo/branches/feature", text: $viewModel.targetURL)
                    .textFieldStyle(.roundedBorder)
            }

            if viewModel.localChangeCount > 0 {
                Label(
                    "工作副本有 \(viewModel.localChangeCount) 项本地修改，切换前建议先提交或还原",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

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
                        if await viewModel.switchBranch(workingCopy: workingCopy) {
                            await onComplete()
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("切换")
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
}
