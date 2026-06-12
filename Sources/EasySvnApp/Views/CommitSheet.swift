import SwiftUI

/// 提交面板：填写日志、复用最近日志。
struct CommitSheet: View {
    let fileCount: Int
    let recentMessages: [String]
    /// 执行提交，成功返回 true。
    let onCommit: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isCommitting = false

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("提交 \(fileCount) 个文件")
                .font(.headline)

            TextEditor(text: $message)
                .font(.body)
                .frame(minHeight: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary)
                )
                .overlay(alignment: .topLeading) {
                    if message.isEmpty {
                        Text("输入提交日志…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                if !recentMessages.isEmpty {
                    Menu("最近日志") {
                        ForEach(recentMessages, id: \.self) { recent in
                            Button {
                                message = recent
                            } label: {
                                Text(recent)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .fixedSize()
                }
                if trimmedMessage.isEmpty {
                    Text("提交日志不能为空")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task {
                        isCommitting = true
                        defer { isCommitting = false }
                        if await onCommit(trimmedMessage) {
                            dismiss()
                        }
                    }
                } label: {
                    if isCommitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("提交")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedMessage.isEmpty || isCommitting)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
