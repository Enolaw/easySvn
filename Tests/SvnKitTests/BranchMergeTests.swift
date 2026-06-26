import Foundation
import Testing
@testable import SvnKit

@Suite("RepositoryURLBuilder")
struct RepositoryURLBuilderTests {

    @Test("构造分支 URL")
    func branchURL() {
        let url = RepositoryURLBuilder.destinationURL(
            repositoryRoot: "https://svn.example.com/repo",
            kind: .branch,
            name: "feature-x"
        )
        #expect(url == "https://svn.example.com/repo/branches/feature-x")
    }

    @Test("构造标签 URL")
    func tagURL() {
        let url = RepositoryURLBuilder.destinationURL(
            repositoryRoot: "file:///tmp/repo/",
            kind: .tag,
            name: "v1.0"
        )
        #expect(url == "file:///tmp/repo/tags/v1.0")
    }

    @Test("误粘贴 URL 时提取最后一段作为名称")
    func sanitizePastedURL() {
        let name = RepositoryURLBuilder.sanitizeCopyName(
            "https://svn.example.com/repo/project/03_SourceCodes/app/3.11.0"
        )
        #expect(name == "3.11.0")
    }

    @Test("03_SourceCodes 布局推断标签目标")
    func inferredTagFromSourceCodesLayout() {
        let source = "https://svn.example.com/application/Proj/03_SourceCodes/my-app/trunk"
        let url = RepositoryURLBuilder.inferredDestinationURL(
            sourceURL: source,
            repositoryRoot: "https://svn.example.com/application",
            kind: .tag,
            name: "3.11.0"
        )
        #expect(url == "https://svn.example.com/application/Proj/03_SourceCodes/03_Tag/my-app/3.11.0")
    }

    @Test("05_SourceCodes 布局推断标签目标")
    func inferredTagFrom05SourceCodesLayout() {
        let source = "https://svn.example.com/application/TeamB/05_SourceCodes/my-app/trunk"
        let url = RepositoryURLBuilder.inferredDestinationURL(
            sourceURL: source,
            repositoryRoot: "https://svn.example.com/application",
            kind: .tag,
            name: "3.11.0"
        )
        #expect(url == "https://svn.example.com/application/TeamB/05_SourceCodes/03_Tag/my-app/3.11.0")
    }

    @Test("来源路径含 03_Tag 时仍推断到正确标签目录")
    func inferredTagWhenSourceContainsTagFolder() {
        let source = "https://svn.example.com/repo/Proj/05_SourceCodes/03_Tag/my-app/4.9.0"
        let url = RepositoryURLBuilder.inferredDestinationURL(
            sourceURL: source,
            repositoryRoot: "https://svn.example.com/repo",
            kind: .tag,
            name: "4.10.0"
        )
        #expect(url == "https://svn.example.com/repo/Proj/05_SourceCodes/03_Tag/my-app/4.10.0")
    }

    @Test("目标仅为 Tag 目录时自动追加版本号")
    func resolvedCopyDestinationAppendsName() {
        let base = "https://svn.example.com/repo/05_SourceCodes/03_Tag/my-app"
        let url = RepositoryURLBuilder.resolvedCopyDestination(baseURL: base, name: "3.11.0")
        #expect(url == "https://svn.example.com/repo/05_SourceCodes/03_Tag/my-app/3.11.0")
    }
}

@Suite("MergeinfoParser")
struct MergeinfoParserTests {

    @Test("解析版本列表")
    func revisions() {
        let text = """
        r3
        r5
        r10
        """
        #expect(MergeinfoParser.parseRevisions(text) == [3, 5, 10])
    }
}

@Suite("SvnClient 分支与合并")
struct BranchMergeIntegrationTests {

    @Test("copy 创建分支并可 switch")
    func copyAndSwitch() async throws {
        let setup = try await TestRepository.make()
        defer { setup.cleanup() }

        try setup.write("readme.txt", contents: "hello\n")
        try await setup.client.add(paths: ["readme.txt"], in: setup.workingCopy)
        _ = try await setup.client.commit(message: "init", in: setup.workingCopy)

        let info = try await setup.client.info(at: setup.workingCopy)
        let branchURL = RepositoryURLBuilder.destinationURL(
            repositoryRoot: info.repositoryRoot,
            kind: .branch,
            name: "test-branch"
        )

        _ = try await setup.client.copyBranchOrTag(
            from: info.url,
            to: branchURL,
            kind: .branch,
            repositoryRoot: info.repositoryRoot,
            message: "create branch"
        )

        let entries = try await setup.client.list(branchURL)
        #expect(entries.contains { $0.name == "readme.txt" })

        _ = try await setup.client.switchTo(branchURL, in: setup.workingCopy)
        let afterSwitch = try await setup.client.info(at: setup.workingCopy)
        #expect(afterSwitch.url == branchURL)
    }

    @Test("merge 分支变更到工作副本")
    func mergeBranch() async throws {
        let setup = try await TestRepository.make()
        defer { setup.cleanup() }

        try setup.write("file.txt", contents: "trunk\n")
        try await setup.client.add(paths: ["file.txt"], in: setup.workingCopy)
        _ = try await setup.client.commit(message: "init", in: setup.workingCopy)

        let info = try await setup.client.info(at: setup.workingCopy)
        let branchURL = RepositoryURLBuilder.destinationURL(
            repositoryRoot: info.repositoryRoot,
            kind: .branch,
            name: "dev"
        )
        _ = try await setup.client.copyBranchOrTag(
            from: info.url,
            to: branchURL,
            kind: .branch,
            repositoryRoot: info.repositoryRoot,
            message: "branch"
        )

        let branchWC = setup.root.appendingPathComponent("branch-wc")
        try await setup.client.checkout(repository: branchURL, to: branchWC)
        try "branch change\n".write(
            to: branchWC.appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try await setup.client.commit(message: "on branch", in: branchWC)

        // 回到 trunk 工作副本合并
        _ = try await setup.client.switchTo(info.url, in: setup.workingCopy)
        _ = try await setup.client.merge(source: branchURL, in: setup.workingCopy)

        let content = try String(
            contentsOf: setup.workingCopy.appendingPathComponent("file.txt"),
            encoding: .utf8
        )
        #expect(content == "branch change\n")
    }
}
