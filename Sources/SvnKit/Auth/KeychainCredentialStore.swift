import Foundation
import Security

/// 凭据存储抽象（便于测试时用内存实现替换）。
public protocol CredentialStore: Sendable {
    /// 保存凭据，同一 realm 已存在时覆盖。
    func save(_ credentials: SvnCredentials, for realm: String) throws
    /// 读取凭据，不存在时返回 nil。
    func load(for realm: String) throws -> SvnCredentials?
    /// 删除凭据，不存在时静默成功。
    func delete(for realm: String) throws
}

public enum CredentialStoreError: Error, Equatable {
    case keychainFailure(OSStatus)
    case corruptedData
}

/// 基于 macOS Keychain 的凭据存储。
///
/// realm 建议使用服务器标识（如 `https://svn.example.com:443`），
/// 存储为 kSecClassGenericPassword：service = 固定前缀 + realm，account = 用户名。
public struct KeychainCredentialStore: CredentialStore {

    private let servicePrefix: String

    public init(servicePrefix: String = "com.easysvn.credential") {
        self.servicePrefix = servicePrefix
    }

    private func service(for realm: String) -> String {
        "\(servicePrefix).\(realm)"
    }

    public func save(_ credentials: SvnCredentials, for realm: String) throws {
        try delete(for: realm)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: realm),
            kSecAttrAccount as String: credentials.username,
            kSecValueData as String: Data(credentials.password.utf8)
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainFailure(status)
        }
    }

    public func load(for realm: String) throws -> SvnCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: realm),
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainFailure(status)
        }
        guard
            let dict = item as? [String: Any],
            let username = dict[kSecAttrAccount as String] as? String,
            let passwordData = dict[kSecValueData as String] as? Data,
            let password = String(data: passwordData, encoding: .utf8)
        else {
            throw CredentialStoreError.corruptedData
        }
        return SvnCredentials(username: username, password: password)
    }

    public func delete(for realm: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: realm)
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainFailure(status)
        }
    }
}
