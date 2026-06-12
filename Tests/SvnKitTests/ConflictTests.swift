import Foundation
import Testing
@testable import SvnKit

@Suite("ConflictFileResolver")
struct ConflictFileResolverTests {

    @Test("读取 mine / base / theirs 辅助文件")
    func loadAuxiliaryFiles() throws {
        let root = TestRepository.baseTempDirectory()
            .appendingPathComponent("conflict-resolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("foo.txt")
        try "working <<<<<<<\nmine\n=======\ntheirs\n>>>>>>>\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "mine content".write(to: root.appendingPathComponent("foo.txt.mine"), atomically: true, encoding: .utf8)
        try "base content".write(to: root.appendingPathComponent("foo.txt.r2"), atomically: true, encoding: .utf8)
        try "theirs content".write(to: root.appendingPathComponent("foo.txt.r5"), atomically: true, encoding: .utf8)

        let versions = ConflictFileResolver.loadVersions(for: "foo.txt", in: root)
        #expect(versions.mine == "mine content")
        #expect(versions.base == "base content")
        #expect(versions.theirs == "theirs content")
        #expect(versions.working?.contains("<<<<<<<") == true)
    }
}

@Suite("SvnClient 冲突")
struct ConflictIntegrationTests {

    @Test("update 产生文本冲突并可 resolve")
    func textConflictResolve() async throws {
        let setup = try await TestRepository.make()
        defer { setup.cleanup() }

        try setup.write("file.txt", contents: "base\n")
        try await setup.client.add(paths: ["file.txt"], in: setup.workingCopy)
        _ = try await setup.client.commit(message: "init", in: setup.workingCopy)

        try setup.write("file.txt", contents: "local change\n")

        let wc2Root = setup.root.appendingPathComponent("wc2")
        try await setup.client.checkout(repository: setup.repositoryURL, to: wc2Root)
        try "remote change\n".write(
            to: wc2Root.appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try await setup.client.commit(message: "remote", in: wc2Root)

        do {
            _ = try await setup.client.update(at: setup.workingCopy)
        } catch {
            // update 可能以非零退出码结束，但冲突文件仍应存在
        }

        let status = try await setup.client.status(at: setup.workingCopy)
        let conflicted = status.first { $0.path == "file.txt" }
        #expect(conflicted?.itemStatus == .conflicted)

        let versions = setup.client.conflictVersions(for: "file.txt", in: setup.workingCopy)
        #expect(versions.hasTextConflict)

        try await setup.client.resolve(
            paths: ["file.txt"],
            accept: .mineFull,
            in: setup.workingCopy
        )

        let after = try await setup.client.status(at: setup.workingCopy)
        #expect(!after.contains { $0.path == "file.txt" && $0.itemStatus == .conflicted })
    }
}
