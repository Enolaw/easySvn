import SwiftUI
import SvnKit

/// 认证失败或证书不受信任时的凭据输入面板。
struct AuthPromptSheet: View {
    let request: AuthPromptRequest
    @ObservedObject var authStore: AuthSettingsStore

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var trustCertificate = true
    @State private var saveToKeychain = true
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("需要认证")
                .font(.headline)

            Text(request.repositoryURL.displayDecodedURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            if request.needsCertTrust {
                Label("服务器证书未受信任", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Toggle("信任此服务器证书并记住", isOn: $trustCertificate)
            }

            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)

            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)

            Toggle("保存到钥匙串", isOn: $saveToKeychain)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") {
                    authStore.dismissAuthPrompt()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("确定")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || username.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear(perform: loadExistingCredentials)
    }

    private func loadExistingCredentials() {
        if let credentials = authStore.credentials(for: request.realm) {
            username = credentials.username
            password = credentials.password
        }
        if request.needsCertTrust {
            trustCertificate = true
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            if request.needsCertTrust, trustCertificate {
                authStore.setTrustServerCert(true, for: request.realm)
            }
            let credentials = SvnCredentials(username: username, password: password)
            if saveToKeychain {
                try authStore.saveCredentials(credentials, for: request.realm)
            } else {
                authStore.setSessionCredentials(credentials, for: request.realm)
            }
            authStore.dismissAuthPrompt()
            dismiss()
            await request.onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
