import Foundation

/// 探测系统中可用的 svn / svnadmin 可执行文件。
public enum SvnBinaryLocator {

    /// 环境变量覆盖（便于测试与用户自定义）。
    public static let svnPathEnvKey = "EASYSVN_SVN_PATH"

    /// 常见安装路径，按优先级排列：Homebrew (Apple Silicon) > Homebrew (Intel) > 系统。
    static let searchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin"
    ]

    /// 查找 svn 可执行文件。
    public static func locateSvn(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if let override = environment[svnPathEnvKey], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        return locate(named: "svn")
    }

    /// 查找同目录下的配套工具（如 svnadmin、svnversion）。
    public static func locate(named name: String) -> URL? {
        for directory in searchDirectories {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path).resolvingSymlinksInPath()
            }
        }
        return nil
    }
}
