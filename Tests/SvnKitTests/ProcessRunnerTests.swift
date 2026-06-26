import Foundation
import Testing
@testable import SvnKit

@Suite("ProcessRunner")
struct ProcessRunnerTests {

    @Test("捕获标准输出")
    func capturesStdout() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello", "world"]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdoutText == "hello world\n")
        #expect(result.standardError.isEmpty)
    }

    @Test("捕获标准错误与非零退出码")
    func capturesStderrAndExitCode() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo oops 1>&2; exit 3"]
        )
        #expect(result.exitCode == 3)
        #expect(result.stderrText == "oops\n")
    }

    @Test("指定工作目录")
    func respectsCurrentDirectory() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/pwd"),
            arguments: [],
            currentDirectory: URL(fileURLWithPath: "/private/tmp")
        )
        #expect(result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines) == "/private/tmp")
    }

    @Test("缺少 locale 时自动补全 UTF-8")
    func injectsUTF8Locale() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/printenv"),
            arguments: ["LANG", "LC_ALL"],
            environment: [
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/bin:/bin",
                "LANG": "",
                "LC_ALL": "",
                "LC_CTYPE": "",
            ]
        )
        #expect(result.exitCode == 0)
        let lines = result.stdoutText.split(separator: "\n").map(String.init)
        #expect(lines.contains("en_US.UTF-8"))
    }

    @Test("可执行文件不存在时抛错")
    func launchFailure() async {
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/nonexistent/binary"),
                arguments: []
            )
        }
    }

    @Test("大输出不丢失数据")
    func largeOutput() async throws {
        // 256 KB 输出，验证管道流式读取不截断
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "yes x | head -c 262144"]
        )
        #expect(result.standardOutput.count == 262_144)
    }
}
