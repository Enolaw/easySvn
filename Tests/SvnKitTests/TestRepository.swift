import Foundation
import SvnKit

struct TestSetupError: Error, CustomStringConvertible {
    let description: String
}

/// 测试辅助：用 svnadmin 在临时目录创建本地仓库并检出工作副本。
struct TestRepository {
    let root: URL
    let repositoryURL: String
    let workingCopy: URL
    let client: SvnClient

    /// 测试临时目录：优先使用 EASYSVN_TEST_TMP 环境变量（CI/沙盒下指向工作区内目录）。
    static func baseTempDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["EASYSVN_TEST_TMP"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.temporaryDirectory
    }

    static func make() async throws -> TestRepository {
        let client = try SvnClient.detect()
        guard let svnadmin = SvnBinaryLocator.locate(named: "svnadmin") else {
            throw TestSetupError(description: "找不到 svnadmin，无法创建测试仓库")
        }

        let root = baseTempDirectory()
            .appendingPathComponent("easysvn-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let repoDir = root.appendingPathComponent("repo")
        let createResult = try await ProcessRunner.run(
            executable: svnadmin,
            arguments: ["create", repoDir.path]
        )
        guard createResult.exitCode == 0 else {
            throw TestSetupError(description: "svnadmin create 失败: \(createResult.stderrText)")
        }

        let repositoryURL = "file://" + repoDir.path
        let workingCopy = root.appendingPathComponent("wc")
        try await client.checkout(repository: repositoryURL, to: workingCopy)

        return TestRepository(
            root: root,
            repositoryURL: repositoryURL,
            workingCopy: workingCopy,
            client: client
        )
    }

    /// 在工作副本中写入文件。
    func write(_ name: String, contents: String) throws {
        try contents.write(
            to: workingCopy.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
