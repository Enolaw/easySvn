import Testing
@testable import SvnKit

@Suite("RepositoryPathResolver")
struct RepositoryPathResolverTests {

    private let info = SvnInfo(
        kind: "dir",
        url: "http://example.com/svn/repo/12_组/09_王",
        relativeURL: "^/12_组/09_王",
        repositoryRoot: "http://example.com/svn/repo",
        repositoryUUID: "uuid",
        revision: 100,
        workingCopyRoot: "/Users/test/wc"
    )

    @Test("日志路径转为工作副本相对路径")
    func workingCopyRelativePath() {
        let relative = RepositoryPathResolver.workingCopyRelativePath(
            logPath: "/12_组/09_王/卡面交接/联调.md",
            wcInfo: info
        )
        #expect(relative == "卡面交接/联调.md")
    }

    @Test("工作副本根路径")
    func wcRootPath() {
        let relative = RepositoryPathResolver.workingCopyRelativePath(
            logPath: "/12_组/09_王",
            wcInfo: info
        )
        #expect(relative == ".")
    }

    @Test("不在工作副本下的路径返回 nil")
    func outOfScopePath() {
        let relative = RepositoryPathResolver.workingCopyRelativePath(
            logPath: "/other/branch/file.txt",
            wcInfo: info
        )
        #expect(relative == nil)
    }

    @Test("构造完整仓库 URL")
    func absoluteFileURL() {
        let url = RepositoryPathResolver.absoluteFileURL(
            logPath: "/12_组/09_王/卡面交接/联调.md",
            wcInfo: info
        )
        #expect(url == "http://example.com/svn/repo/12_组/09_王/卡面交接/联调.md")
    }
}
