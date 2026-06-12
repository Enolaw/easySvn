import AppKit
import Foundation
import SvnKit

enum ExternalDiffKind {
    case workingCopy(path: String)
    case revision(revision: Int, path: String, action: SvnChangeAction? = nil)
}

/// 调用外部 diff 工具（FileMerge、Beyond Compare 等）。
@MainActor
enum ExternalDiffService {

    static func open(
        kind: ExternalDiffKind,
        workingCopy: WorkingCopy,
        settings: AppSettingsStore,
        authStore: AuthSettingsStore
    ) async throws {
        guard settings.hasExternalDiffTool else {
            throw ExternalDiffError.toolNotConfigured
        }

        let client = try authStore.makeClient(forRepositoryURL: workingCopy.path)
        let pair = try await DiffAssetLoader.loadDataPair(
            kind: kind,
            workingCopy: workingCopy,
            client: client
        )
        let (left, right) = try DiffAssetLoader.writeToTempFiles(pair, pathHint: pathHint(for: kind))
        defer {
            cleanupTempFiles([left, right])
        }

        try launch(
            executable: settings.externalDiffExecutable,
            argumentsTemplate: settings.externalDiffArguments,
            left: left,
            right: right
        )
    }

    static func launch(
        executable: String,
        argumentsTemplate: String,
        left: URL,
        right: URL
    ) throws {
        let trimmedExecutable = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExecutable.isEmpty else {
            throw ExternalDiffError.toolNotConfigured
        }

        let args = ExternalDiffArgumentBuilder.build(
            template: argumentsTemplate,
            left: left,
            right: right
        )

        let process = Process()
        if trimmedExecutable.hasSuffix(".app") || trimmedExecutable.contains(".app/") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", trimmedExecutable] + args
        } else {
            process.executableURL = URL(fileURLWithPath: trimmedExecutable)
            process.arguments = args
        }
        try process.run()
    }

    private static func pathHint(for kind: ExternalDiffKind) -> String {
        switch kind {
        case .workingCopy(let path): path
        case .revision(let revision, let logPath, _):
            "r\(revision)-\(logPath)"
        }
    }

    private static func cleanupTempFiles(_ urls: [URL]) {
        for url in urls where url.path.contains("easysvn-diff-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

enum ExternalDiffArgumentBuilder {
    static func build(template: String, left: URL, right: URL) -> [String] {
        let expanded = template
            .replacingOccurrences(of: "%left", with: left.path)
            .replacingOccurrences(of: "%right", with: right.path)
            .replacingOccurrences(of: "%mine", with: right.path)
            .replacingOccurrences(of: "%theirs", with: left.path)
            .replacingOccurrences(of: "%base", with: left.path)
            .replacingOccurrences(of: "%1", with: left.path)
            .replacingOccurrences(of: "%2", with: right.path)

        return expanded
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

enum ExternalDiffError: LocalizedError {
    case toolNotConfigured
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotConfigured:
            return "请先在设置中配置外部 diff 工具"
        case .launchFailed(let message):
            return message
        }
    }
}
