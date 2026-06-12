import Foundation

/// SVN 用户名密码凭据。
public struct SvnCredentials: Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// 认证相关选项，注入到每条 svn 命令。
public struct SvnAuthOptions: Sendable, Equatable {
    /// 用户名密码（nil 时使用 svn 自身的认证缓存）。
    public var credentials: SvnCredentials?
    /// 是否信任服务器证书校验失败（自签名证书场景，配合 --non-interactive）。
    public var trustServerCertFailures: Bool
    /// 是否禁止 svn 将凭据写入其自身的明文缓存（默认禁止，凭据由 App 的 Keychain 管理）。
    public var noAuthCache: Bool

    public init(
        credentials: SvnCredentials? = nil,
        trustServerCertFailures: Bool = false,
        noAuthCache: Bool = true
    ) {
        self.credentials = credentials
        self.trustServerCertFailures = trustServerCertFailures
        self.noAuthCache = noAuthCache
    }

    /// 生成命令行参数。
    var arguments: [String] {
        var args: [String] = []
        if let credentials {
            args += ["--username", credentials.username, "--password", credentials.password]
            if noAuthCache {
                args.append("--no-auth-cache")
            }
        }
        if trustServerCertFailures {
            args.append("--trust-server-cert-failures=unknown-ca,cn-mismatch,expired,not-yet-valid,other")
        }
        return args
    }
}
