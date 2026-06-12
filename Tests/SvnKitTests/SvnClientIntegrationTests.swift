import Foundation
import Testing
@testable import SvnKit

/// 端到端集成测试：基于 svnadmin 创建的本地 file:// 仓库。
@Suite("SvnClient 集成", .serialized)
struct SvnClientIntegrationTests {

    @Test("探测 svn 并获取版本号")
    func detectAndVersion() async throws {
        let client = try SvnClient.detect()
        let version = try await client.version()
        // 形如 "1.14.5"
        #expect(version.range(of: #"^\d+\.\d+"#, options: .regularExpression) != nil)
    }

    @Test("checkout 创建有效工作副本")
    func checkout() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }

        let svnDir = repo.workingCopy.appendingPathComponent(".svn")
        #expect(FileManager.default.fileExists(atPath: svnDir.path))

        let info = try await repo.client.info(at: repo.workingCopy)
        #expect(info.kind == "dir")
        #expect(info.revision == 0)
        #expect(info.repositoryRoot == repo.repositoryURL)
        #expect(info.workingCopyRoot == repo.workingCopy.path
            || info.workingCopyRoot == "/private" + repo.workingCopy.path)
    }

    @Test("add + commit + status 全流程")
    func addCommitStatus() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        // 1. 新文件未版本控制
        try repo.write("hello.txt", contents: "hello\n")
        var entries = try await client.status(at: repo.workingCopy)
        #expect(entries.count == 1)
        #expect(entries[0].path == "hello.txt")
        #expect(entries[0].itemStatus == .unversioned)

        // 2. add 后状态变为 added
        try await client.add(paths: ["hello.txt"], in: repo.workingCopy)
        entries = try await client.status(at: repo.workingCopy)
        #expect(entries[0].itemStatus == .added)

        // 3. commit 返回版本号 1，提交后无变更
        let revision = try await client.commit(message: "add hello.txt", in: repo.workingCopy)
        #expect(revision == 1)
        entries = try await client.status(at: repo.workingCopy)
        #expect(entries.isEmpty)

        // 4. 修改文件后状态为 modified
        try repo.write("hello.txt", contents: "hello again\n")
        entries = try await client.status(at: repo.workingCopy)
        #expect(entries.count == 1)
        #expect(entries[0].itemStatus == .modified)
        #expect(entries[0].commitRevision == 1)

        // 5. revert 还原修改
        try await client.revert(paths: ["hello.txt"], in: repo.workingCopy)
        entries = try await client.status(at: repo.workingCopy)
        #expect(entries.isEmpty)
    }

    @Test("info 反映最后一次提交")
    func infoAfterCommit() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        try repo.write("a.txt", contents: "a\n")
        try await client.add(paths: ["a.txt"], in: repo.workingCopy)
        try await client.commit(message: "first commit", in: repo.workingCopy)
        try await client.update(at: repo.workingCopy)

        let info = try await client.info(at: repo.workingCopy)
        #expect(info.revision == 1)
        #expect(info.lastCommitRevision == 1)
        #expect(info.lastCommitAuthor != nil)
    }

    @Test("非工作副本目录报 E155007")
    func notAWorkingCopy() async throws {
        let client = try SvnClient.detect()
        let dir = TestRepository.baseTempDirectory()
            .appendingPathComponent("easysvn-notwc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        await #expect {
            _ = try await client.info(at: dir)
        } throws: { error in
            (error as? SvnError)?.code == SvnError.Code.notAWorkingCopy
        }
    }
}
