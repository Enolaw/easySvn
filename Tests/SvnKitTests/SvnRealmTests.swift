import Testing
@testable import SvnKit

@Suite("SvnRealm")
struct SvnRealmTests {

    @Test("https URL 提取 scheme host port")
    func httpsRealm() {
        #expect(SvnRealm.from(repositoryURL: "https://svn.example.com/repo/trunk") == "https://svn.example.com:443")
    }

    @Test("http 自定义端口")
    func customPort() {
        #expect(SvnRealm.from(repositoryURL: "http://svn.example.com:8080/repo") == "http://svn.example.com:8080")
    }

    @Test("file URL 保持原样")
    func fileURL() {
        let url = "file:///tmp/repo"
        #expect(SvnRealm.from(repositoryURL: url) == url)
    }
}
