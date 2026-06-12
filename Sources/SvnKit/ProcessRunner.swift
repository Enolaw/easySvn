import Foundation

/// 子进程执行结果。
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public var stdoutText: String { String(decoding: standardOutput, as: UTF8.self) }
    public var stderrText: String { String(decoding: standardError, as: UTF8.self) }
}

public enum ProcessRunnerError: Error, Sendable, Equatable {
    case launchFailed(String)
}

/// 线程安全的数据累积缓冲区，供 Pipe 的 readabilityHandler 回调使用。
private final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Process 不是 Sendable，用包装类跨并发域传递（仅用于取消时 terminate）。
private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

/// 异步子进程执行器：流式收集 stdout/stderr，支持通过 Task 取消终止进程。
public enum ProcessRunner {

    public static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let stdoutBuffer = DataBuffer()
        let stderrBuffer = DataBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stdoutBuffer.append(chunk) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stderrBuffer.append(chunk) }
        }

        let box = ProcessBox(process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    // 进程退出后排空管道中残留的数据
                    if let rest = try? stdoutPipe.fileHandleForReading.readToEnd(), !rest.isEmpty {
                        stdoutBuffer.append(rest)
                    }
                    if let rest = try? stderrPipe.fileHandleForReading.readToEnd(), !rest.isEmpty {
                        stderrBuffer.append(rest)
                    }
                    continuation.resume(returning: ProcessResult(
                        exitCode: proc.terminationStatus,
                        standardOutput: stdoutBuffer.snapshot(),
                        standardError: stderrBuffer.snapshot()
                    ))
                }
                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            if box.process.isRunning {
                box.process.terminate()
            }
        }
    }
}
