import Testing
@testable import SvnKit

@Suite("RepositoryURLHelper")
struct RepositoryURLHelperTests {

    @Test("解码 URL 中的中文路径")
    func displayDecodedChinesePath() {
        let encoded = "https://svn.example.com/repo/%E5%8D%A1%E9%9D%A2%E4%B8%9A%E5%8A%A1/trunk"
        #expect(
            RepositoryURLHelper.displayDecoded(encoded)
                == "https://svn.example.com/repo/卡面业务/trunk"
        )
    }

    @Test("已解码 URL 保持不变")
    func displayDecodedPassthrough() {
        let plain = "https://svn.example.com/repo/卡面业务/trunk"
        #expect(RepositoryURLHelper.displayDecoded(plain) == plain)
    }

    @Test("lastComponent 返回解码后的目录名")
    func lastComponentDecodes() {
        let url = "https://svn.example.com/repo/%E5%8D%A1%E9%9D%A2%E4%B8%9A%E5%8A%A1"
        #expect(RepositoryURLHelper.lastComponent(of: url) == "卡面业务")
    }
}
