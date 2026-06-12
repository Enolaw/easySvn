import SwiftUI
import SvnKit

/// 应用设置：外观、外部工具、自动刷新、认证。
struct SettingsView: View {
    @EnvironmentObject private var authStore: AuthSettingsStore
    @EnvironmentObject private var appSettings: AppSettingsStore

    @State private var editingRealm: String?
    @State private var editUsername = ""
    @State private var editPassword = ""
    @State private var settingsError: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
            externalToolsTab
                .tabItem { Label("外部工具", systemImage: "arrow.left.arrow.right") }
            credentialsTab
                .tabItem { Label("认证", systemImage: "key") }
        }
        .frame(width: 520, height: 400)
        .sheet(item: $editingRealm) { realm in
            credentialEditor(for: realm)
        }
        .alert("操作失败", isPresented: Binding(
            get: { settingsError != nil },
            set: { if !$0 { settingsError = nil } }
        )) {
            Button("好") { settingsError = nil }
        } message: {
            Text(settingsError ?? "")
        }
    }

    private var generalTab: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appSettings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                Picker("语言", selection: $appSettings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                Text("完整界面翻译将在 v1.0 提供；当前语言偏好主要影响日期与数字格式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("状态刷新") {
                Toggle("文件变更时自动刷新状态", isOn: $authStore.autoRefreshEnabled)
                Toggle("显示已忽略的文件", isOn: $appSettings.showIgnored)
                Text("监听工作副本目录的文件系统事件，在本地修改后自动更新变更列表。开启「显示已忽略」后，变更列表会包含 svn:ignore 匹配项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var externalToolsTab: some View {
        Form {
            Section("Diff 工具") {
                Picker("预设", selection: $appSettings.externalDiffPreset) {
                    ForEach(ExternalDiffPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .onChange(of: appSettings.externalDiffPreset) { preset in
                    appSettings.applyDiffPreset(preset)
                }

                if appSettings.externalDiffPreset != .none {
                    TextField("可执行文件路径", text: $appSettings.externalDiffExecutable)
                    TextField("参数模板", text: $appSettings.externalDiffArguments)
                    Text("占位符：%left（旧/Base）、%right（新/工作副本）、%mine、%theirs、%base、%1、%2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("优先使用外部工具查看差异", isOn: $appSettings.preferExternalDiff)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var credentialsTab: some View {
        Form {
            if authStore.knownRealms.isEmpty {
                Text("暂无已保存的凭据。首次连接需要认证的服务器时会提示保存。")
                    .foregroundStyle(.secondary)
            } else {
                Section("已保存凭据") {
                    ForEach(authStore.knownRealms, id: \.self) { realm in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(realm)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let username = authStore.credentials(for: realm)?.username {
                                    Text(username)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if authStore.isCertTrusted(for: realm) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(.green)
                                    .help("已信任服务器证书")
                            }
                            Button("编辑") { beginEdit(realm) }
                            Button("删除", role: .destructive) { deleteRealm(realm) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func credentialEditor(for realm: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑凭据")
                .font(.headline)
            Text(realm)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            TextField("用户名", text: $editUsername)
                .textFieldStyle(.roundedBorder)
            SecureField("密码", text: $editPassword)
                .textFieldStyle(.roundedBorder)

            Toggle("信任服务器证书", isOn: Binding(
                get: { authStore.isCertTrusted(for: realm) },
                set: { authStore.setTrustServerCert($0, for: realm) }
            ))

            HStack {
                Spacer()
                Button("取消") { editingRealm = nil }
                Button("保存") { saveEdit(realm) }
                    .buttonStyle(.borderedProminent)
                    .disabled(editUsername.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func beginEdit(_ realm: String) {
        editingRealm = realm
        if let credentials = authStore.credentials(for: realm) {
            editUsername = credentials.username
            editPassword = credentials.password
        } else {
            editUsername = ""
            editPassword = ""
        }
    }

    private func saveEdit(_ realm: String) {
        do {
            try authStore.saveCredentials(
                SvnCredentials(username: editUsername, password: editPassword),
                for: realm
            )
            editingRealm = nil
        } catch {
            settingsError = error.localizedDescription
        }
    }

    private func deleteRealm(_ realm: String) {
        do {
            try authStore.deleteCredentials(for: realm)
            authStore.setTrustServerCert(false, for: realm)
        } catch {
            settingsError = error.localizedDescription
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
