import Foundation

/// SVN 客户端：对 svn 命令行的异步封装。
///
/// 所有命令以 `--non-interactive` 运行，失败时抛出归一化的 ``SvnError``。
public struct SvnClient: Sendable {

    /// svn 可执行文件路径。
    public let executable: URL
    /// 认证选项（凭据、证书信任），注入到每条命令。
    public let authOptions: SvnAuthOptions

    public init(executable: URL, authOptions: SvnAuthOptions = SvnAuthOptions()) {
        self.executable = executable
        self.authOptions = authOptions
    }

    /// 自动探测系统中的 svn。
    public static func detect(authOptions: SvnAuthOptions = SvnAuthOptions()) throws -> SvnClient {
        guard let url = SvnBinaryLocator.locateSvn() else {
            throw SvnKitError.svnNotFound
        }
        return SvnClient(executable: url, authOptions: authOptions)
    }

    /// 返回携带指定凭据的新客户端。
    public func withCredentials(_ credentials: SvnCredentials?) -> SvnClient {
        var options = authOptions
        options.credentials = credentials
        return SvnClient(executable: executable, authOptions: options)
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

    /// 提交日志。
    /// - Parameters:
    ///   - target: 工作副本路径或仓库 URL。
    ///   - limit: 最多返回条数（分页加载用）。
    ///   - revisionRange: 版本范围（如 "HEAD:1"、"5:1"），nil 为默认。
    ///   - verbose: 是否包含每个版本的变更文件列表。
    public func log(
        at target: String,
        limit: Int? = nil,
        revisionRange: String? = nil,
        verbose: Bool = true
    ) async throws -> [SvnLogEntry] {
        var args = ["log", "--xml", target]
        if verbose {
            args.append("--verbose")
        }
        if let limit {
            args += ["--limit", String(limit)]
        }
        if let revisionRange {
            args += ["--revision", revisionRange]
        }
        let result = try await run(args)
        return try LogXMLParser.parse(result.standardOutput)
    }

    /// 列出仓库目录内容（不检出，仓库浏览器用）。
    public func list(_ target: String, revision: String? = nil) async throws -> [SvnListEntry] {
        var args = ["list", "--xml", target]
        if let revision {
            args += ["--revision", revision]
        }
        let result = try await run(args)
        return try ListXMLParser.parse(result.standardOutput)
    }

    /// 读取文件内容（可指定版本，查看历史版本用）。
    public func cat(_ target: String, revision: String? = nil) async throws -> Data {
        var args = ["cat", target]
        if let revision {
            args += ["--revision", revision]
        }
        let result = try await run(args)
        return result.standardOutput
    }

    /// 统一 diff 文本（不带参数为整个工作副本的本地修改）。
    public func diff(at workingCopy: URL, paths: [String] = []) async throws -> String {
        let result = try await run(["diff"] + paths, in: workingCopy)
        return result.stdoutText
    }

    /// 查看某次提交对指定路径的变更（`svn diff -c REV path`）。
    public func diffChange(revision: Int, path: String, in workingCopy: URL) async throws -> String {
        let result = try await run(["diff", "-c", String(revision), path], in: workingCopy)
        return result.stdoutText
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

    /// 更新工作副本（可指定路径），返回更新后的版本号（无法解析时为 nil）。
    @discardableResult
    public func update(at workingCopy: URL, paths: [String] = [], revision: String? = nil) async throws -> Int? {
        var args = ["update"]
        if let revision {
            args += ["--revision", revision]
        }
        args += paths
        let result = try await run(args, in: workingCopy)
        // 输出末行形如 "Updated to revision 5." 或 "At revision 5."
        if let range = result.stdoutText.range(
            of: #"(Updated to|At) revision (\d+)"#,
            options: .regularExpression
        ) {
            return Int(result.stdoutText[range].filter(\.isNumber))
        }
        return nil
    }

    /// 还原本地修改。
    public func revert(paths: [String], recursive: Bool = false, in workingCopy: URL) async throws {
        var args = ["revert"]
        if recursive {
            args.append("--depth=infinity")
        }
        try await run(args + paths, in: workingCopy)
    }

    /// 删除受版本控制的文件/目录。
    public func delete(paths: [String], in workingCopy: URL) async throws {
        try await run(["delete"] + paths, in: workingCopy)
    }

    /// 受版本控制的移动/重命名。
    public func move(from source: String, to destination: String, in workingCopy: URL) async throws {
        try await run(["move", source, destination], in: workingCopy)
    }

    /// 清理工作副本（解除残留锁定）。
    public func cleanup(at workingCopy: URL) async throws {
        try await run(["cleanup"], in: workingCopy)
    }

    /// 导出干净副本（不含 .svn）。
    public func export(_ target: String, to destination: URL, revision: String? = nil) async throws {
        var args = ["export", target, destination.path]
        if let revision {
            args += ["--revision", revision]
        }
        try await run(args)
    }

    // MARK: - 底层执行

    /// 组装最终命令行参数（业务参数 + 认证参数 + --non-interactive）。
    func makeArguments(_ arguments: [String]) -> [String] {
        arguments + authOptions.arguments + ["--non-interactive"]
    }

    @discardableResult
    func run(_ arguments: [String], in directory: URL? = nil) async throws -> ProcessResult {
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: makeArguments(arguments),
            currentDirectory: directory
        )
        guard result.exitCode == 0 else {
            throw SvnError.parse(from: result)
        }
        return result
    }
}
