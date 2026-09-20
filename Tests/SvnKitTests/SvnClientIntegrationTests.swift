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

    @Test("含 @ 的文件名可正常 add / commit / diff / revert")
    func atSignFilename() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        // 前端构建产物常见的 @2x 命名，路径里的 @ 会被 svn 误解析为 peg 版本
        let name = "button-前往我的@2x.ed418296.png"

        // 1. add + commit
        try repo.write(name, contents: "image-bytes\n")
        try await client.add(paths: [name], in: repo.workingCopy)
        let revision = try await client.commit(message: "add @2x asset", in: repo.workingCopy)
        #expect(revision == 1)
        var entries = try await client.status(at: repo.workingCopy)
        #expect(entries.isEmpty)

        // 2. 修改后 status 能识别（含 @ 路径不被误判为 peg 版本）
        try repo.write(name, contents: "image-bytes-v2\n")
        entries = try await client.status(at: repo.workingCopy)
        #expect(entries.count == 1)
        #expect(entries[0].itemStatus == .modified)

        // 3. 本地 diff（无版本参数，使用原始路径）
        let localDiff = try await client.diff(at: repo.workingCopy)
        #expect(localDiff.contains("-image-bytes"))
        #expect(localDiff.contains("+image-bytes-v2"))

        // 4. 指定版本的 diff（带 -c，需对含 @ 路径转义）
        let changeDiff = try await client.diffChange(revision: 1, path: name, in: repo.workingCopy)
        #expect(changeDiff.contains("button-前往我的"))

        // 5. revert
        try await client.revert(paths: [name], in: repo.workingCopy)
        entries = try await client.status(at: repo.workingCopy)
        #expect(entries.isEmpty)
    }

    @Test("escapingPegRevision 仅对含 @ 的路径追加末尾 @")
    func escapingPegRevision() {
        #expect(SvnClient.escapingPegRevision("a/b/c.png") == "a/b/c.png")
        #expect(SvnClient.escapingPegRevision("icon@2x.png") == "icon@2x.png@")
        #expect(SvnClient.escapingPegRevisions(["a.png", "b@2x.png"]) == ["a.png", "b@2x.png@"])
    }

    @Test("嵌套 dist 路径可用 --parents 加入版本控制")
    func nestedDistAddWithParents() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        let distDir = repo.workingCopy.appendingPathComponent("project/4.10.1/production/dist/img", isDirectory: true)
        try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
        try "img\n".write(to: distDir.appendingPathComponent("icon.png"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: repo.workingCopy.appendingPathComponent("project/4.10.1/src"),
            withIntermediateDirectories: true
        )
        try repo.write("project/4.10.1/src/main.js", contents: "src\n")

        try await client.add(paths: ["project/4.10.1/production/dist"], in: repo.workingCopy)
        let entries = try await client.status(at: repo.workingCopy)
        #expect(entries.contains { $0.path == "project/4.10.1/production/dist/img/icon.png" && $0.itemStatus == .added })
        #expect(entries.contains { $0.path == "project/4.10.1/src" && $0.itemStatus == .unversioned })
    }

    @Test("dist 目录内已有受控文件时可用 --force 继续添加新文件")
    func mixedDistAddWithForce() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        let distDir = repo.workingCopy.appendingPathComponent("project/4.10.1/prod/dist/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
        try "old\n".write(to: distDir.appendingPathComponent("old.js"), atomically: true, encoding: .utf8)
        try await client.add(paths: ["project/4.10.1/prod/dist"], in: repo.workingCopy)
        try await client.commit(message: "base dist", in: repo.workingCopy)
        try "new\n".write(to: distDir.appendingPathComponent("new.js"), atomically: true, encoding: .utf8)

        try await client.add(
            paths: ["project/4.10.1/prod/dist"],
            force: true,
            in: repo.workingCopy
        )
        let entries = try await client.status(at: repo.workingCopy)
        #expect(entries.contains { $0.path == "project/4.10.1/prod/dist/assets/new.js" && $0.itemStatus == .added })
    }

    @Test("混合文件列表使用 --force 时忽略已受控项且退出成功")
    func mixedFileListAddWithForce() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        let distDir = repo.workingCopy.appendingPathComponent("ui/3.11.1/test/dist/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
        try "old\n".write(to: distDir.appendingPathComponent("old.js"), atomically: true, encoding: .utf8)
        try "html\n".write(
            to: repo.workingCopy.appendingPathComponent("ui/3.11.1/test/dist/index.html"),
            atomically: true,
            encoding: .utf8
        )
        try await client.add(paths: ["ui/3.11.1/test/dist"], in: repo.workingCopy)
        try await client.commit(message: "base", in: repo.workingCopy)
        try "new\n".write(to: distDir.appendingPathComponent("new.js"), atomically: true, encoding: .utf8)

        try await client.add(
            paths: [
                "ui/3.11.1/test/dist/assets/old.js",
                "ui/3.11.1/test/dist/assets/new.js",
                "ui/3.11.1/test/dist/index.html",
            ],
            force: true,
            in: repo.workingCopy
        )
        let entries = try await client.status(at: repo.workingCopy)
        #expect(entries.contains { $0.path == "ui/3.11.1/test/dist/assets/new.js" && $0.itemStatus == .added })
    }

    @Test("info 反映最后一次提交")
    func infoAfterCommit() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        try repo.write("a.txt", contents: "a\n")
        try await client.add(paths: ["a.txt"], in: repo.workingCopy)
        try await client.commit(message: "first commit", in: repo.workingCopy)
        let updatedRevision = try await client.update(at: repo.workingCopy)
        #expect(updatedRevision == 1)

        let info = try await client.info(at: repo.workingCopy)
        #expect(info.revision == 1)
        #expect(info.lastCommitRevision == 1)
        #expect(info.lastCommitAuthor != nil)
    }

    @Test("log 返回提交历史与变更文件")
    func log() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        try repo.write("a.txt", contents: "a\n")
        try await client.add(paths: ["a.txt"], in: repo.workingCopy)
        try await client.commit(message: "first: add a.txt", in: repo.workingCopy)

        try repo.write("a.txt", contents: "a changed\n")
        try await client.commit(message: "second: modify a.txt", in: repo.workingCopy)

        // svn log 对工作副本默认查到其 BASE 版本为止，需先 update 推进根目录版本
        try await client.update(at: repo.workingCopy)

        let entries = try await client.log(at: repo.workingCopy.path)
        #expect(entries.count == 2)
        // 默认倒序：最新在前
        #expect(entries[0].revision == 2)
        #expect(entries[0].message == "second: modify a.txt")
        #expect(entries[0].changedPaths.count == 1)
        #expect(entries[0].changedPaths[0].action == .modified)
        #expect(entries[1].revision == 1)
        #expect(entries[1].changedPaths[0].action == .added)

        // limit 分页
        let limited = try await client.log(at: repo.workingCopy.path, limit: 1)
        #expect(limited.count == 1)
        #expect(limited[0].revision == 2)
    }

    @Test("list 浏览远程仓库目录")
    func list() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        try repo.write("readme.txt", contents: "hello\n")
        try FileManager.default.createDirectory(
            at: repo.workingCopy.appendingPathComponent("src"),
            withIntermediateDirectories: true
        )
        try repo.write("src/main.swift", contents: "print(1)\n")
        try await client.add(paths: ["readme.txt", "src"], in: repo.workingCopy)
        try await client.commit(message: "init", in: repo.workingCopy)

        let entries = try await client.list(repo.repositoryURL)
        #expect(entries.count == 2)

        let dir = try #require(entries.first { $0.name == "src" })
        #expect(dir.kind == .dir)
        let file = try #require(entries.first { $0.name == "readme.txt" })
        #expect(file.kind == .file)
        #expect(file.size == 6)
        #expect(file.commitRevision == 1)
    }

    @Test("cat 读取指定版本内容")
    func cat() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        try repo.write("v.txt", contents: "version 1\n")
        try await client.add(paths: ["v.txt"], in: repo.workingCopy)
        try await client.commit(message: "r1", in: repo.workingCopy)
        try repo.write("v.txt", contents: "version 2\n")
        try await client.commit(message: "r2", in: repo.workingCopy)

        let head = try await client.cat(repo.repositoryURL + "/v.txt")
        #expect(String(decoding: head, as: UTF8.self) == "version 2\n")

        let old = try await client.cat(repo.repositoryURL + "/v.txt", revision: "1")
        #expect(String(decoding: old, as: UTF8.self) == "version 1\n")
    }

    @Test("diff 输出本地修改")
    func diff() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        try repo.write("d.txt", contents: "old line\n")
        try await client.add(paths: ["d.txt"], in: repo.workingCopy)
        try await client.commit(message: "base", in: repo.workingCopy)

        try repo.write("d.txt", contents: "new line\n")
        let output = try await client.diff(at: repo.workingCopy)
        #expect(output.contains("-old line"))
        #expect(output.contains("+new line"))
    }

    @Test("delete / move / cleanup / export")
    func fileOperations() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        try repo.write("del.txt", contents: "x\n")
        try repo.write("old-name.txt", contents: "y\n")
        try await client.add(paths: ["del.txt", "old-name.txt"], in: repo.workingCopy)
        try await client.commit(message: "base", in: repo.workingCopy)

        // delete：状态变为 deleted
        try await client.delete(paths: ["del.txt"], in: repo.workingCopy)
        var entries = try await client.status(at: repo.workingCopy)
        let deleted = try #require(entries.first { $0.path == "del.txt" })
        #expect(deleted.itemStatus == .deleted)

        // move：旧路径 deleted，新路径 added 且标记为复制
        try await client.move(from: "old-name.txt", to: "new-name.txt", in: repo.workingCopy)
        entries = try await client.status(at: repo.workingCopy)
        let moved = try #require(entries.first { $0.path == "new-name.txt" })
        #expect(moved.itemStatus == .added)
        #expect(moved.isCopied)

        try await client.commit(message: "delete + rename", in: repo.workingCopy)

        // cleanup 正常执行
        try await client.cleanup(at: repo.workingCopy)

        // export：导出目录不含 .svn
        let exportDir = repo.root.appendingPathComponent("exported")
        try await client.export(repo.repositoryURL, to: exportDir)
        #expect(FileManager.default.fileExists(atPath: exportDir.appendingPathComponent("new-name.txt").path))
        #expect(!FileManager.default.fileExists(atPath: exportDir.appendingPathComponent(".svn").path))
        #expect(!FileManager.default.fileExists(atPath: exportDir.appendingPathComponent("del.txt").path))

        let fileDest = repo.root.appendingPathComponent("exported-file.txt")
        try "placeholder".write(to: fileDest, atomically: true, encoding: .utf8)
        try await client.export(repo.repositoryURL + "/new-name.txt", to: fileDest)
        #expect(try String(contentsOf: fileDest, encoding: .utf8).contains("y"))
    }

    @Test("目录 svn:ignore 变更显示为属性已修改且可提交")
    func propsOnlyDirectoryCommit() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        try FileManager.default.createDirectory(
            at: repo.workingCopy.appendingPathComponent("tools"),
            withIntermediateDirectories: true
        )
        try repo.write("tools/readme.txt", contents: "ok\n")
        try await client.add(paths: ["tools"], in: repo.workingCopy)
        try await client.commit(message: "add tools", in: repo.workingCopy)

        try await client.appendIgnore(patterns: [".venv"], at: "tools", in: repo.workingCopy)
        let entries = try await client.status(at: repo.workingCopy)
        let tools = try #require(entries.first { $0.path == "tools" })
        #expect(tools.isPropsOnlyModified)
        #expect(tools.isCommittable)

        let revision = try await client.commit(paths: ["tools"], message: "ignore venv", in: repo.workingCopy)
        #expect(revision == 2)
        let after = try await client.status(at: repo.workingCopy)
        #expect(after.isEmpty)
    }

    @Test("svn:ignore 显示已忽略项并可取消忽略")
    func ignoreRoundTrip() async throws {
        let repo = try await TestRepository.make()
        defer { repo.cleanup() }
        let client = repo.client

        try repo.write("skip.txt", contents: "ignored\n")
        try await client.appendIgnore(patterns: ["skip.txt"], at: ".", in: repo.workingCopy)

        var entries = try await client.status(at: repo.workingCopy, includeIgnored: true)
        let ignored = try #require(entries.first { $0.path == "skip.txt" })
        #expect(ignored.itemStatus == .ignored)

        entries = try await client.status(at: repo.workingCopy, includeIgnored: false)
        #expect(entries.first { $0.path == "skip.txt" } == nil)

        try await client.removeIgnore(patterns: ["skip.txt"], at: ".", in: repo.workingCopy)
        entries = try await client.status(at: repo.workingCopy, includeIgnored: true)
        let unversioned = try #require(entries.first { $0.path == "skip.txt" })
        #expect(unversioned.itemStatus == .unversioned)
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
