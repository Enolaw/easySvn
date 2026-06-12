import SwiftUI

/// 远程重命名。
struct RenameRemoteSheet: View {
    let currentName: String
    let onRename: (String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var newName: String
    @State private var message = ""
    @State private var isSubmitting = false

    init(currentName: String, onRename: @escaping (String, String) async -> Bool) {
        self.currentName = currentName
        self.onRename = onRename
        _newName = State(initialValue: currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("重命名")
                .font(.headline)
            Text("当前：\(currentName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("新名称", text: $newName)
                .textFieldStyle(.roundedBorder)

            TextField("提交日志", text: $message)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button {
                    Task {
                        isSubmitting = true
                        defer { isSubmitting = false }
                        if await onRename(newName, message) {
                            dismiss()
                        }
                    }
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("重命名")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.isEmpty || message.isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            if message.isEmpty { message = "重命名 \(currentName)" }
        }
    }
}
