import SwiftUI
import SvnKit

/// Checkout 向导面板。
struct CheckoutSheet: View {
    @ObservedObject var viewModel: CheckoutViewModel
    let onComplete: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("检出工作副本")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("仓库 URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://svn.example.com/repo/trunk", text: $viewModel.repositoryURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isCheckingOut)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("本地目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("选择或输入路径", text: $viewModel.destinationPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isCheckingOut)
                    Button("浏览…") { viewModel.chooseDestination() }
                        .disabled(viewModel.isCheckingOut)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("检出深度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $viewModel.depth) {
                        ForEach(SvnDepth.allCases) { depth in
                            Text(depth.displayName).tag(depth)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .disabled(viewModel.isCheckingOut)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("指定版本", isOn: $viewModel.useSpecificRevision)
                        .disabled(viewModel.isCheckingOut)
                    if viewModel.useSpecificRevision {
                        TextField("HEAD 或版本号", text: $viewModel.revision)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .disabled(viewModel.isCheckingOut)
                    }
                }
            }

            if viewModel.isCheckingOut {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(viewModel.progressText.isEmpty ? "正在检出…" : viewModel.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                if viewModel.isCheckingOut {
                    Button("取消") { viewModel.cancel() }
                } else {
                    Button("关闭") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button {
                        Task {
                            if let url = await viewModel.checkout() {
                                onComplete(url)
                                dismiss()
                            }
                        }
                    } label: {
                        Text("检出")
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canCheckout)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
