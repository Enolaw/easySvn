import SwiftUI

/// 远程仓库操作通用的提交日志输入面板。
struct RemoteMessageSheet: View {
    let title: String
    let prompt: String
    let confirmLabel: String
    let isDestructive: Bool
    let onConfirm: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(prompt)
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("提交日志", text: $message)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button {
                    Task {
                        isSubmitting = true
                        defer { isSubmitting = false }
                        if await onConfirm(message.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            dismiss()
                        }
                    }
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(confirmLabel)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(isDestructive ? .red : nil)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
