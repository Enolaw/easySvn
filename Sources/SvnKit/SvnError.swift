import Foundation

/// 归一化的 SVN 错误：从 svn 命令的退出码和 stderr 中提取错误码与可读信息。
public struct SvnError: Error, Sendable, Equatable, CustomStringConvertible {
    /// 进程退出码。
    public let exitCode: Int32
    /// SVN 错误码（如 stderr 中 `svn: E155007:` 的 155007），无法识别时为 nil。
    public let code: Int?
    /// 错误信息（stderr 原文，已去除首尾空白）。
    public let message: String

    public var description: String {
        if let code {
            return "svn error E\(code): \(message)"
        }
        return "svn error (exit \(exitCode)): \(message)"
    }

    /// 常见错误码。
    public enum Code {
        public static let notAWorkingCopy = 155007
        public static let workingCopyLocked = 155004
        public static let authnFailed = 170001
        public static let connectionRefused = 175002
    }

    public init(exitCode: Int32, code: Int?, message: String) {
        self.exitCode = exitCode
        self.code = code
        self.message = message
    }

    /// 从进程结果解析 SVN 错误。
    public static func parse(from result: ProcessResult) -> SvnError {
        let stderr = result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        var code: Int?
        // 匹配第一处 "svn: E123456:" 形式的错误码
        if let range = stderr.range(of: #"svn: E(\d+):"#, options: .regularExpression) {
            code = Int(stderr[range].filter(\.isNumber))
        }
        let message = stderr.isEmpty ? "svn exited with code \(result.exitCode)" : stderr
        return SvnError(exitCode: result.exitCode, code: code, message: message)
    }
}

/// SvnKit 自身的错误。
public enum SvnKitError: Error, Sendable, Equatable {
    /// 找不到可用的 svn 可执行文件。
    case svnNotFound
    /// XML 输出解析失败。
    case xmlParseFailed(String)
}
