import Foundation
import SwiftUI
import SvnKit

/// 认证弹窗请求（认证失败或证书不受信任时展示）。
struct AuthPromptRequest: Identifiable {
    let id = UUID()
    let realm: String
    let repositoryURL: String
    var needsCertTrust: Bool
    let onComplete: () async -> Void
}

/// 全局认证与证书信任设置，凭据存 Keychain。
@MainActor
final class AuthSettingsStore: ObservableObject {

    private static let knownRealmsKey = "authKnownRealms"
    private static let trustedCertRealmsKey = "trustedCertRealms"
    private static let autoRefreshKey = "autoRefreshEnabled"

    @Published private(set) var knownRealms: [String] = []
    @Published private(set) var trustedCertRealms: Set<String> = []
    @Published var autoRefreshEnabled: Bool {
        didSet { AppUserDefaults.shared.set(autoRefreshEnabled, forKey: Self.autoRefreshKey) }
    }
    @Published var pendingAuthPrompt: AuthPromptRequest?

    private let credentialStore: any CredentialStore
    private var sessionCredentials: [String: SvnCredentials] = [:]

    init(credentialStore: any CredentialStore = KeychainCredentialStore()) {
        self.credentialStore = credentialStore
        knownRealms = AppUserDefaults.shared.stringArray(forKey: Self.knownRealmsKey) ?? []
        if let trusted = AppUserDefaults.shared.stringArray(forKey: Self.trustedCertRealmsKey) {
            trustedCertRealms = Set(trusted)
        } else {
            trustedCertRealms = []
        }
        if AppUserDefaults.shared.object(forKey: Self.autoRefreshKey) == nil {
            autoRefreshEnabled = true
        } else {
            autoRefreshEnabled = AppUserDefaults.shared.bool(forKey: Self.autoRefreshKey)
        }
    }

    // MARK: - 客户端构造

    func makeClient(forRepositoryURL url: String?) throws -> SvnClient {
        let base = try SvnClient.detect()
        guard let url, !url.isEmpty else { return base }
        return applyAuth(to: base, realm: SvnRealm.from(repositoryURL: url))
    }

    func makeClient(forInfo info: SvnInfo) throws -> SvnClient {
        try makeClient(forRepositoryURL: info.repositoryRoot.isEmpty ? info.url : info.repositoryRoot)
    }

    func setSessionCredentials(_ credentials: SvnCredentials?, for realm: String) {
        if let credentials {
            sessionCredentials[realm] = credentials
        } else {
            sessionCredentials.removeValue(forKey: realm)
        }
    }

    private func applyAuth(to client: SvnClient, realm: String) -> SvnClient {
        var options = client.authOptions
        if let credentials = sessionCredentials[realm] ?? (try? credentialStore.load(for: realm)) {
            options.credentials = credentials
        }
        options.trustServerCertFailures = trustedCertRealms.contains(realm)
        return SvnClient(executable: client.executable, authOptions: options)
    }

    // MARK: - 凭据管理

    func credentials(for realm: String) -> SvnCredentials? {
        try? credentialStore.load(for: realm)
    }

    func saveCredentials(_ credentials: SvnCredentials, for realm: String) throws {
        try credentialStore.save(credentials, for: realm)
        rememberRealm(realm)
    }

    func deleteCredentials(for realm: String) throws {
        try credentialStore.delete(for: realm)
        knownRealms.removeAll { $0 == realm }
        AppUserDefaults.shared.set(knownRealms, forKey: Self.knownRealmsKey)
    }

    func setTrustServerCert(_ trusted: Bool, for realm: String) {
        if trusted {
            trustedCertRealms.insert(realm)
        } else {
            trustedCertRealms.remove(realm)
        }
        AppUserDefaults.shared.set(Array(trustedCertRealms).sorted(), forKey: Self.trustedCertRealmsKey)
    }

    func isCertTrusted(for realm: String) -> Bool {
        trustedCertRealms.contains(realm)
    }

    private func rememberRealm(_ realm: String) {
        guard !knownRealms.contains(realm) else { return }
        knownRealms.append(realm)
        knownRealms.sort()
        AppUserDefaults.shared.set(knownRealms, forKey: Self.knownRealmsKey)
    }

    // MARK: - 认证弹窗

    func presentAuthPrompt(
        repositoryURL: String,
        needsCertTrust: Bool,
        retry: @escaping () async -> Void
    ) {
        let realm = SvnRealm.from(repositoryURL: repositoryURL)
        pendingAuthPrompt = AuthPromptRequest(
            realm: realm,
            repositoryURL: repositoryURL,
            needsCertTrust: needsCertTrust,
            onComplete: retry
        )
    }

    func dismissAuthPrompt() {
        pendingAuthPrompt = nil
    }

    func shouldPrompt(for error: Error, repositoryURL: String) -> (needsPrompt: Bool, needsCertTrust: Bool) {
        guard let svnError = error as? SvnError else { return (false, false) }
        let realm = SvnRealm.from(repositoryURL: repositoryURL)
        if svnError.isCertificateError, !trustedCertRealms.contains(realm) {
            return (true, true)
        }
        if svnError.isAuthenticationError {
            return (true, false)
        }
        return (false, false)
    }
}
