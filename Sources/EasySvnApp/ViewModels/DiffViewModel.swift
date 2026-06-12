import Foundation
import SvnKit

/// Diff 视图数据加载。
@MainActor
final class DiffViewModel: ObservableObject {

    enum Source {
        /// 工作副本本地修改（相对 BASE）。
        case workingCopy(path: String)
        /// 某次提交中的变更（日志 verbose 输出的仓库路径）。
        case revision(revision: Int, path: String)
    }

    let source: Source
    let title: String

    @Published private(set) var lines: [DiffLine] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isEmpty = false

    init(source: Source, title: String) {
        self.source = source
        self.title = title
    }

    func load(workingCopy: WorkingCopy) async {
        isLoading = true
        errorMessage = nil
        isEmpty = false
        defer { isLoading = false }

        do {
            let client = try SvnClient.detect()
            let text: String
            switch source {
            case .workingCopy(let path):
                text = try await client.diff(at: workingCopy.directoryURL, paths: [path])
            case .revision(let revision, let logPath):
                let info = try await client.info(at: workingCopy.directoryURL)
                text = try await Self.loadRevisionDiff(
                    client: client,
                    revision: revision,
                    logPath: logPath,
                    info: info,
                    workingCopy: workingCopy
                )
            }
            applyDiffText(text)
        } catch let error as SvnError {
            errorMessage = Self.friendlyMessage(for: error)
        } catch SvnKitError.svnNotFound {
            errorMessage = "找不到 svn 命令行工具"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDiffText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isEmpty = true
            lines = []
        } else {
            lines = UnifiedDiffParser.parse(text)
        }
    }

    /// 优先用工作副本相对路径 diff；失败则用仓库 URL（本地文件不存在时仍可查看）。
    private static func loadRevisionDiff(
        client: SvnClient,
        revision: Int,
        logPath: String,
        info: SvnInfo,
        workingCopy: WorkingCopy
    ) async throws -> String {
        if let relative = RepositoryPathResolver.workingCopyRelativePath(logPath: logPath, wcInfo: info) {
            do {
                return try await client.diffChange(
                    revision: revision,
                    path: relative,
                    in: workingCopy.directoryURL
                )
            } catch {
                // 本地路径不可用（文件缺失、路径不一致等）时回退到仓库 URL
            }
        }

        let url = RepositoryPathResolver.absoluteFileURL(logPath: logPath, wcInfo: info)
        return try await client.diffChange(
            revision: revision,
            path: url,
            in: workingCopy.directoryURL
        )
    }

    private static func friendlyMessage(for error: SvnError) -> String {
        switch error.code {
        case 155010:
            return "找不到该文件，可能已被删除或路径不一致"
        default:
            return error.message
        }
    }
}
