import Foundation

/// SVN 客户端：对 svn 命令行的异步封装。
///
/// 所有命令以 `--non-interactive` 运行，失败时抛出归一化的 ``SvnError``。
public struct SvnClient: Sendable {

    /// svn 可执行文件路径。
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// 自动探测系统中的 svn。
    public static func detect() throws -> SvnClient {
        guard let url = SvnBinaryLocator.locateSvn() else {
            throw SvnKitError.svnNotFound
        }
        return SvnClient(executable: url)
    }

    // MARK: - 查询命令

    /// svn 客户端版本号（如 "1.14.5"）。
    public func version() async throws -> String {
        let result = try await run(["--version", "--quiet"])
        return result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 工作副本状态（仅变更项，不含 normal 状态文件）。
    public func status(at workingCopy: URL) async throws -> [SvnStatusEntry] {
        let result = try await run(["status", "--xml"], in: workingCopy)
        return try StatusXMLParser.parse(result.standardOutput)
    }

    /// 工作副本或仓库 URL 的信息。
    public func info(at path: URL) async throws -> SvnInfo {
        let target = path.isFileURL ? path.path : path.absoluteString
        let result = try await run(["info", "--xml", target])
        return try InfoXMLParser.parse(result.standardOutput)
    }

    // MARK: - 修改命令

    /// 检出仓库到本地目录。
    public func checkout(repository: String, to directory: URL, revision: String? = nil) async throws {
        var args = ["checkout", repository, directory.path]
        if let revision {
            args += ["--revision", revision]
        }
        try await run(args)
    }

    /// 将文件加入版本控制。
    public func add(paths: [String], in workingCopy: URL) async throws {
        try await run(["add"] + paths, in: workingCopy)
    }

    /// 提交，返回新版本号（无法解析时为 nil）。
    @discardableResult
    public func commit(paths: [String] = [], message: String, in workingCopy: URL) async throws -> Int? {
        let args = ["commit", "--message", message] + paths
        let result = try await run(args, in: workingCopy)
        // 输出末行形如 "Committed revision 5."
        if let range = result.stdoutText.range(of: #"Committed revision (\d+)"#, options: .regularExpression) {
            let digits = result.stdoutText[range].filter(\.isNumber)
            return Int(digits)
        }
        return nil
    }

    /// 更新工作副本。
    public func update(at workingCopy: URL, revision: String? = nil) async throws {
        var args = ["update"]
        if let revision {
            args += ["--revision", revision]
        }
        try await run(args, in: workingCopy)
    }

    /// 还原本地修改。
    public func revert(paths: [String], recursive: Bool = false, in workingCopy: URL) async throws {
        var args = ["revert"]
        if recursive {
            args.append("--depth=infinity")
        }
        try await run(args + paths, in: workingCopy)
    }

    // MARK: - 底层执行

    @discardableResult
    func run(_ arguments: [String], in directory: URL? = nil) async throws -> ProcessResult {
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments + ["--non-interactive"],
            currentDirectory: directory
        )
        guard result.exitCode == 0 else {
            throw SvnError.parse(from: result)
        }
        return result
    }
}
