import Foundation
import Testing
@testable import SvnKit

@Suite("SvnAuthOptions")
struct SvnAuthOptionsTests {

    @Test("无凭据时不注入认证参数")
    func noCredentials() {
        let options = SvnAuthOptions()
        #expect(options.arguments.isEmpty)
    }

    @Test("凭据注入用户名密码并禁用缓存")
    func withCredentials() {
        let options = SvnAuthOptions(credentials: SvnCredentials(username: "alice", password: "s3cret"))
        #expect(options.arguments == ["--username", "alice", "--password", "s3cret", "--no-auth-cache"])
    }

    @Test("信任证书失败选项")
    func trustServerCert() {
        let options = SvnAuthOptions(trustServerCertFailures: true)
        #expect(options.arguments.count == 1)
        #expect(options.arguments[0].hasPrefix("--trust-server-cert-failures="))
    }

    @Test("SvnClient 组装最终参数")
    func clientArguments() {
        let client = SvnClient(executable: URL(fileURLWithPath: "/usr/bin/svn"))
            .withCredentials(SvnCredentials(username: "alice", password: "pw"))
        let args = client.makeArguments(["status", "--xml"])
        #expect(args == [
            "status", "--xml",
            "--username", "alice", "--password", "pw", "--no-auth-cache",
            "--non-interactive"
        ])
    }
}

@Suite("KeychainCredentialStore", .serialized)
struct KeychainCredentialStoreTests {

    /// 测试专用前缀 + 随机 realm，避免污染真实钥匙串条目。
    let store = KeychainCredentialStore(servicePrefix: "com.easysvn.test")

    @Test("保存/读取/覆盖/删除 全流程")
    func roundtrip() throws {
        let realm = "https://test.example.com:\(UUID().uuidString)"
        defer { try? store.delete(for: realm) }

        // 不存在时返回 nil
        #expect(try store.load(for: realm) == nil)

        // 保存并读取
        try store.save(SvnCredentials(username: "alice", password: "pw1"), for: realm)
        #expect(try store.load(for: realm) == SvnCredentials(username: "alice", password: "pw1"))

        // 覆盖保存
        try store.save(SvnCredentials(username: "bob", password: "pw2"), for: realm)
        #expect(try store.load(for: realm) == SvnCredentials(username: "bob", password: "pw2"))

        // 删除后读取为 nil，重复删除不报错
        try store.delete(for: realm)
        #expect(try store.load(for: realm) == nil)
        try store.delete(for: realm)
    }
}
