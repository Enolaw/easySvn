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
