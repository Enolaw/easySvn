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

    /// 全量状态扫描超时（含误 add 巨型目录时避免无限等待）。
    public static let statusTimeout: TimeInterval = 90

    /// 工作副本状态（仅变更项，不含 normal 状态文件）。
    /// - Parameters:
    ///   - paths: 非空时仅扫描指定相对路径（大目录增量刷新用）。
    ///   - includeIgnored: 为 true 时附带 `svn:ignore` 匹配项（`--no-ignore`）。
    public func status(
        at workingCopy: URL,
        paths: [String] = [],
        includeIgnored: Bool = false
    ) async throws -> [SvnStatusEntry] {
        let timeout = paths.isEmpty ? Self.statusTimeout : nil
        var args = ["status", "--xml"]
        if includeIgnored {
            args.append("--no-ignore")
        }
        args += Self.escapingPegRevisions(paths)
        let result = try await run(args, in: workingCopy, timeout: timeout)
        return try StatusXMLParser.parse(result.standardOutput)
    }

    /// 工作副本或仓库 URL 的信息。
    public func info(at path: URL) async throws -> SvnInfo {
        let target = path.isFileURL ? Self.escapingPegRevision(path.path) : path.absoluteString
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

    /// 读取工作副本内相对路径的 peg 版本内容（如 `foo.txt@BASE`、`bar@12`）。
    public func cat(path: String, pegRevision: String, in workingCopy: URL) async throws -> Data {
        let result = try await run(["cat", "\(path)@\(pegRevision)"], in: workingCopy)
        return result.standardOutput
    }

    /// 统一 diff 文本（不带参数为整个工作副本的本地修改）。
    ///
    /// 注意：不带版本参数的 `svn diff` 不会对工作副本路径做 peg 解析，
    /// 因此这里必须传原始路径，**不能**追加末尾 `@`（否则报 E155010）。
    public func diff(at workingCopy: URL, paths: [String] = []) async throws -> String {
        let result = try await run(["diff"] + paths, in: workingCopy)
        return result.stdoutText
    }

    /// 查看某次提交对指定路径的变更（`svn diff -c REV path`）。
    /// 带 `-c` 时 `svn diff` 会对路径做 peg 解析，故含 `@` 的路径需转义。
    public func diffChange(revision: Int, path: String, in workingCopy: URL) async throws -> String {
        let result = try await run(
            ["diff", "-c", String(revision), Self.escapingPegRevision(path)],
            in: workingCopy
        )
        return result.stdoutText
    }

    // MARK: - 修改命令

    /// 检出仓库到本地目录。
    public func checkout(
        repository: String,
        to directory: URL,
        revision: String? = nil,
        depth: SvnDepth? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        var args = ["checkout", repository, directory.path]
        if let revision {
            args += ["--revision", revision]
        }
        if let depth {
            args += ["--depth", depth.rawValue]
        }

        if let onProgress {
            let lineBuffer = LineBuffer()
            try await run(args, onStderrChunk: { chunk in
                let text = String(decoding: chunk, as: UTF8.self)
                for line in lineBuffer.append(text) where !line.isEmpty {
                    onProgress(line)
                }
            })
            let tail = lineBuffer.flush().trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                onProgress(tail)
            }
        } else {
            try await run(args)
        }
    }

    /// 将文件加入版本控制。
    /// - Parameter parents: 为 true 时使用 `--parents`，可添加深层路径并自动补全中间目录。
    /// - Parameter force: 为 true 时使用 `--force`，目录内已有受控文件时仍继续添加其余项。
    public func add(
        paths: [String],
        parents: Bool = true,
        force: Bool = false,
        in workingCopy: URL
    ) async throws {
        var args = ["add"]
        if parents {
            args.append("--parents")
        }
        if force {
            args.append("--force")
        }
        try await run(args + Self.escapingPegRevisions(paths), in: workingCopy)
    }

    /// 提交，返回新版本号（无法解析时为 nil）。
    @discardableResult
    public func commit(paths: [String] = [], message: String, in workingCopy: URL) async throws -> Int? {
        let args = ["commit", "--message", message] + Self.escapingPegRevisions(paths)
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
        args += Self.escapingPegRevisions(paths)
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
        try await run(args + Self.escapingPegRevisions(paths), in: workingCopy)
    }

    /// 删除受版本控制的文件/目录。
    public func delete(paths: [String], in workingCopy: URL) async throws {
        try await run(["delete"] + Self.escapingPegRevisions(paths), in: workingCopy)
    }

    /// 受版本控制的移动/重命名。
    public func move(from source: String, to destination: String, in workingCopy: URL) async throws {
        try await run(
            ["move", Self.escapingPegRevision(source), Self.escapingPegRevision(destination)],
            in: workingCopy
        )
    }

    /// 清理工作副本（解除残留锁定）。
    public func cleanup(at workingCopy: URL) async throws {
        try await run(["cleanup"], in: workingCopy)
    }

    /// 读取目录/文件属性。
    public func propget(_ name: String, at path: String, in workingCopy: URL) async throws -> String? {
        do {
            let result = try await run(["propget", name, Self.escapingPegRevision(path)], in: workingCopy)
            let text = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch let error as SvnError where error.exitCode != 0 {
            return nil
        }
    }

    /// 向目录追加 `svn:ignore` 模式（保留已有项）。
    public func appendIgnore(patterns: [String], at directory: String, in workingCopy: URL) async throws {
        let existing = (try? await propget("svn:ignore", at: directory, in: workingCopy)) ?? ""
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for pattern in patterns where !pattern.isEmpty {
            if !lines.contains(pattern) {
                lines.append(pattern)
            }
        }
        while lines.last == "" {
            lines.removeLast()
        }
        let value = lines.joined(separator: "\n")
        try await run(["propset", "svn:ignore", value, Self.escapingPegRevision(directory)], in: workingCopy)
    }

    /// 从目录的 `svn:ignore` 中移除模式；无剩余项时删除属性。
    public func removeIgnore(patterns: [String], at directory: String, in workingCopy: URL) async throws {
        let existing = (try? await propget("svn:ignore", at: directory, in: workingCopy)) ?? ""
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let removeSet = Set(patterns)
        lines.removeAll { removeSet.contains($0) }
        while lines.last == "" {
            lines.removeLast()
        }
        if lines.isEmpty {
            try await run(["propdel", "svn:ignore", Self.escapingPegRevision(directory)], in: workingCopy)
        } else {
            let value = lines.joined(separator: "\n")
            try await run(["propset", "svn:ignore", value, Self.escapingPegRevision(directory)], in: workingCopy)
        }
    }

    /// 解决冲突（`svn resolve --accept`）。
    public func resolve(
        paths: [String],
        accept: SvnResolveAccept,
        in workingCopy: URL
    ) async throws {
        try await run(
            ["resolve", "--accept=\(accept.rawValue)"] + Self.escapingPegRevisions(paths),
            in: workingCopy
        )
    }

    /// 标记冲突已解决（`svn resolved`）。
    public func markResolved(paths: [String], in workingCopy: URL) async throws {
        try await run(["resolved"] + Self.escapingPegRevisions(paths), in: workingCopy)
    }

    /// 读取冲突文件的三方文本。
    public func conflictVersions(for path: String, in workingCopy: URL) -> ConflictVersions {
        ConflictFileResolver.loadVersions(for: path, in: workingCopy)
    }

    /// 将合并结果写回工作副本文件。
    public func writeConflictResult(_ content: String, for path: String, in workingCopy: URL) throws {
        try ConflictFileResolver.writeWorking(content, for: path, in: workingCopy)
    }

    // MARK: - 分支 / 合并

    /// 在仓库中创建目录（`svn mkdir --parents`）。
    public func mkdir(_ url: String, message: String, parents: Bool = true) async throws {
        var args = ["mkdir"]
        if parents {
            args.append("--parents")
        }
        try await run(args + [url, "--message", message])
    }

    /// 远程删除仓库路径（`svn delete URL -m MSG`）。
    public func deleteRemote(_ url: String, message: String) async throws {
        try await run(["delete", url, "--message", message])
    }

    /// 远程移动/重命名（`svn move SRC DEST -m MSG`）。
    @discardableResult
    public func moveRemote(from source: String, to destination: String, message: String) async throws -> Int? {
        let result = try await run(["move", source, destination, "--message", message])
        return parseCommittedRevision(result.stdoutText)
    }

    /// 仓库内复制（创建分支/标签）：`svn copy SOURCE DEST -m MSG`。
    @discardableResult
    public func copy(from source: String, to destination: String, message: String) async throws -> Int? {
        let result = try await run(["copy", source, destination, "--message", message])
        return parseCommittedRevision(result.stdoutText)
    }

    /// 创建分支/标签：先 copy，仅在父目录不存在时再 mkdir。
    @discardableResult
    public func copyBranchOrTag(
        from source: String,
        to destination: String,
        kind: RepositoryCopyKind,
        repositoryRoot: String,
        message: String
    ) async throws -> Int? {
        do {
            return try await copy(from: source, to: destination, message: message)
        } catch let error as SvnError {
            guard let parent = RepositoryURLHelper.parentURL(of: destination),
                  isMissingParentDirectoryError(error) else {
                throw error
            }
            try await ensureRemoteDirectory(parent, kind: kind)
            return try await copy(from: source, to: destination, message: message)
        }
    }

    private func isMissingParentDirectoryError(_ error: SvnError) -> Bool {
        let lower = error.message.lowercased()
        return lower.contains("not found")
            || lower.contains("does not exist")
            || lower.contains("unable to find")
            || lower.contains("path not found")
    }

    private func remotePathExists(_ url: String) async -> Bool {
        guard let target = URL(string: url) else { return false }
        do {
            _ = try await info(at: target)
            return true
        } catch {
            return false
        }
    }

    private func ensureRemoteDirectory(_ url: String, kind: RepositoryCopyKind) async throws {
        if await remotePathExists(url) { return }
        do {
            try await mkdir(url, message: "ensure \(kind.displayName) parent folder", parents: true)
        } catch let error as SvnError {
            if error.code == 150002 || error.message.localizedCaseInsensitiveContains("already exists") {
                return
            }
            if await remotePathExists(url) { return }
            throw error
        }
    }

    /// 切换工作副本到另一分支 URL。
    @discardableResult
    public func switchTo(_ url: String, in workingCopy: URL) async throws -> Int? {
        let result = try await run(["switch", url], in: workingCopy)
        if let range = result.stdoutText.range(
            of: #"(Updated to|At) revision (\d+)"#,
            options: .regularExpression
        ) {
            return Int(result.stdoutText[range].filter(\.isNumber))
        }
        return nil
    }

    /// 合并（支持版本范围与 dry-run 预览）。
    public func merge(
        source: String,
        in workingCopy: URL,
        revisionRange: String? = nil,
        dryRun: Bool = false
    ) async throws -> String {
        var args = ["merge"]
        if dryRun {
            args.append("--dry-run")
        }
        if let revisionRange {
            args += ["-r", revisionRange]
        }
        args.append(source)
        let result = try await run(args, in: workingCopy)
        return result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 查询 mergeinfo（已合并 / 可合并版本）。
    public func mergeinfo(
        source: String,
        kind: SvnMergeinfoKind,
        in workingCopy: URL
    ) async throws -> [Int] {
        let result = try await run(
            ["mergeinfo", "--show-revs", kind.rawValue, source],
            in: workingCopy
        )
        return MergeinfoParser.parseRevisions(result.stdoutText)
    }

    /// 导出干净副本（不含 .svn）。
    public func export(_ target: String, to destination: URL, revision: String? = nil) async throws {
        var args = ["export", target, destination.path]
        if let revision {
            args += ["--revision", revision]
        }
        try await run(args)
    }

    private func parseCommittedRevision(_ text: String) -> Int? {
        if let range = text.range(of: #"Committed revision (\d+)"#, options: .regularExpression) {
            return Int(text[range].filter(\.isNumber))
        }
        return nil
    }

    // MARK: - Peg 版本转义

    /// 转义路径中的 peg 版本分隔符 `@`。
    ///
    /// SVN 会把路径中最后一个 `@` 之后的内容解析为 peg 版本（如 `foo@12`），
    /// 因此像 `icon@2x.png` 这类含 `@` 的文件名会报
    /// `a peg revision is not allowed here`。在含 `@` 的路径末尾追加一个
    /// 空的 `@` 即可禁用该解析（SVN 官方推荐做法）。
    static func escapingPegRevision(_ path: String) -> String {
        path.contains("@") ? path + "@" : path
    }

    /// 对一组路径批量应用 ``escapingPegRevision(_:)``。
    static func escapingPegRevisions(_ paths: [String]) -> [String] {
        paths.map(escapingPegRevision)
    }

    // MARK: - 底层执行

    /// 组装最终命令行参数（业务参数 + 认证参数 + --non-interactive）。
    func makeArguments(_ arguments: [String]) -> [String] {
        arguments + authOptions.arguments + ["--non-interactive"]
    }

    @discardableResult
    func run(
        _ arguments: [String],
        in directory: URL? = nil,
        onStderrChunk: (@Sendable (Data) -> Void)? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: makeArguments(arguments),
            currentDirectory: directory,
            onStderrChunk: onStderrChunk,
            timeout: timeout
        )
        guard result.exitCode == 0 else {
            throw SvnError.parse(from: result)
        }
        return result
    }
}

/// 线程安全的按行缓冲，供 checkout 进度回调解析 stderr。
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""

    func append(_ text: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pending += text
        var lines: [String] = []
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            pending = String(pending[pending.index(after: newline)...])
            lines.append(line)
        }
        return lines
    }

    func flush() -> String {
        lock.lock()
        defer { lock.unlock() }
        let tail = pending
        pending = ""
        return tail
    }
}
