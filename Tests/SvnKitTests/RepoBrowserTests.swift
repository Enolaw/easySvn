import Foundation
import Testing
@testable import SvnKit

@Suite("RepositoryURLHelper")
struct RepositoryURLHelperTests {

    @Test("拼接子路径")
    func childURL() {
        #expect(
            RepositoryURLHelper.childURL(parent: "https://svn.example.com/repo/trunk", name: "foo")
                == "https://svn.example.com/repo/trunk/foo"
        )
    }

    @Test("提取父路径")
    func parentURL() {
        #expect(
            RepositoryURLHelper.parentURL(of: "file:///tmp/repo/trunk/foo.txt")
                == "file:///tmp/repo/trunk"
        )
    }
}

@Suite("SvnClient 仓库浏览器")
struct RepoBrowserIntegrationTests {

    @Test("远程 mkdir 与 list")
    func remoteMkdirAndList() async throws {
        let setup = try await TestRepository.make()
        defer { setup.cleanup() }

        try setup.write("readme.txt", contents: "hi\n")
        try await setup.client.add(paths: ["readme.txt"], in: setup.workingCopy)
        _ = try await setup.client.commit(message: "init", in: setup.workingCopy)

        let info = try await setup.client.info(at: setup.workingCopy)
        let remoteDir = RepositoryURLHelper.childURL(parent: info.repositoryRoot, name: "remote-dir")
        try await setup.client.mkdir(remoteDir, message: "create remote dir")

        let entries = try await setup.client.list(info.repositoryRoot)
        #expect(entries.contains { $0.name == "remote-dir" && $0.kind == .dir })
        #expect(entries.contains { $0.name == "readme.txt" })
    }

    @Test("远程 delete 与 move")
    func remoteDeleteAndMove() async throws {
        let setup = try await TestRepository.make()
        defer { setup.cleanup() }

        try setup.write("a.txt", contents: "a\n")
        try await setup.client.add(paths: ["a.txt"], in: setup.workingCopy)
        _ = try await setup.client.commit(message: "add file", in: setup.workingCopy)

        let info = try await setup.client.info(at: setup.workingCopy)
        let fileURL = RepositoryURLHelper.childURL(parent: info.url, name: "a.txt")
        let newPath = RepositoryURLHelper.childURL(parent: info.repositoryRoot, name: "new.txt")

        _ = try await setup.client.moveRemote(from: fileURL, to: newPath, message: "rename remote")

        var entries = try await setup.client.list(info.repositoryRoot)
        #expect(entries.contains { $0.name == "new.txt" })
        #expect(!entries.contains { $0.name == "a.txt" })

        try await setup.client.deleteRemote(newPath, message: "delete remote")
        entries = try await setup.client.list(info.repositoryRoot)
        #expect(!entries.contains { $0.name == "new.txt" })
    }

    @Test("cat 读取远程文件")
    func remoteCat() async throws {
        let setup = try await TestRepository.make()
        defer { setup.cleanup() }

        try setup.write("doc.txt", contents: "remote content\n")
        try await setup.client.add(paths: ["doc.txt"], in: setup.workingCopy)
        _ = try await setup.client.commit(message: "add", in: setup.workingCopy)

        let info = try await setup.client.info(at: setup.workingCopy)
        let fileURL = RepositoryURLHelper.childURL(parent: info.url, name: "doc.txt")
        let data = try await setup.client.cat(fileURL)
        #expect(String(data: data, encoding: .utf8) == "remote content\n")
    }
}
