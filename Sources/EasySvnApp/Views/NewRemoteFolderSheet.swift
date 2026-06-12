import SwiftUI

/// 在仓库中新建目录。
struct NewRemoteFolderSheet: View {
    let onCreate: (String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var message = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建目录")
                .font(.headline)

            TextField("目录名", text: $name)
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
                        if await onCreate(name, message) {
                            dismiss()
                        }
                    }
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("创建")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || message.isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            if message.isEmpty { message = "新建目录" }
        }
    }
}
