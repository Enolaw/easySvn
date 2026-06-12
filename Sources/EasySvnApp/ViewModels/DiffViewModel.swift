import Foundation
import SvnKit

enum DiffContentKind {
    case image
    case text
}

enum DiffTextLayout: String, CaseIterable, Identifiable {
    case sideBySide
    case unified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideBySide: "并排"
        case .unified: "统一"
        }
    }
}

/// Diff 视图数据加载。
@MainActor
final class DiffViewModel: ObservableObject {

    enum Source {
        /// 工作副本本地修改（相对 BASE）。
        case workingCopy(path: String)
        /// 某次提交中的变更（日志 verbose 输出的仓库路径）。
        case revision(revision: Int, path: String, action: SvnChangeAction? = nil)
    }

    let source: Source
    let title: String

    @Published private(set) var contentKind: DiffContentKind = .text
    @Published var textLayout: DiffTextLayout = .sideBySide
    @Published private(set) var lines: [DiffLine] = []
    @Published private(set) var sideBySideRows: [SideBySideRow] = []
    @Published private(set) var leftImageData: Data?
    @Published private(set) var rightImageData: Data?
    @Published private(set) var leftLabel = ""
    @Published private(set) var rightLabel = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isEmpty = false

    private weak var authStore: AuthSettingsStore?

    var filePath: String {
        switch source {
        case .workingCopy(let path): path
        case .revision(_, let path, _):
            RepositoryPathResolver.normalizedRepoPath(path)
        }
    }

    init(source: Source, title: String) {
        self.source = source
        self.title = title
    }

    func configure(authStore: AuthSettingsStore) {
        self.authStore = authStore
    }

    func load(workingCopy: WorkingCopy) async {
        isLoading = true
        errorMessage = nil
        isEmpty = false
        defer { isLoading = false }

        do {
            let client = try makeClient(for: workingCopy)
            let kind = externalDiffKind

            if ImageFileDetector.isImage(filePath) {
                try await loadImageDiff(client: client, kind: kind, workingCopy: workingCopy)
            } else {
                try await loadTextDiff(client: client, kind: kind, workingCopy: workingCopy)
            }
        } catch let error as SvnError {
            if !handleAuthFailure(error, workingCopy: workingCopy, retry: { [weak self] in
                await self?.load(workingCopy: workingCopy)
            }) {
                errorMessage = Self.friendlyMessage(for: error)
            }
        } catch SvnKitError.svnNotFound {
            errorMessage = "找不到 svn 命令行工具"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var externalDiffKind: ExternalDiffKind {
        switch source {
        case .workingCopy(let path):
            return .workingCopy(path: path)
        case .revision(let revision, let path, let action):
            return .revision(revision: revision, path: path, action: action)
        }
    }

    private func loadImageDiff(
        client: SvnClient,
        kind: ExternalDiffKind,
        workingCopy: WorkingCopy
    ) async throws {
        let pair = try await DiffAssetLoader.loadDataPair(
            kind: kind,
            workingCopy: workingCopy,
            client: client
        )
        contentKind = .image
        leftImageData = pair.left.isEmpty ? nil : pair.left
        rightImageData = pair.right.isEmpty ? nil : pair.right
        leftLabel = pair.leftLabel
        rightLabel = pair.rightLabel
        lines = []
        sideBySideRows = []
        isEmpty = leftImageData == nil && rightImageData == nil
    }

    private func loadTextDiff(
        client: SvnClient,
        kind: ExternalDiffKind,
        workingCopy: WorkingCopy
    ) async throws {
        contentKind = .text
        leftImageData = nil
        rightImageData = nil
        applyTextLabels(for: kind)

        let text: String
        switch source {
        case .workingCopy(let path):
            text = try await client.diff(at: workingCopy.directoryURL, paths: [path])
        case .revision(let revision, let logPath, _):
            let info = try await client.info(at: workingCopy.directoryURL)
            text = try await Self.loadRevisionDiff(
                client: client,
                revision: revision,
                logPath: logPath,
                info: info,
                workingCopy: workingCopy
            )
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isEmpty = true
            lines = []
            sideBySideRows = []
            return
        }

        if Self.isBinaryDiffMessage(trimmed) {
            let pair = try await DiffAssetLoader.loadDataPair(
                kind: kind,
                workingCopy: workingCopy,
                client: client
            )
            leftLabel = pair.leftLabel
            rightLabel = pair.rightLabel
            let leftText = String(data: pair.left, encoding: .utf8) ?? ""
            let rightText = String(data: pair.right, encoding: .utf8) ?? ""
            sideBySideRows = SideBySideDiffBuilder.buildFromFullText(left: leftText, right: rightText)
            lines = []
            isEmpty = sideBySideRows.isEmpty
            return
        }

        applyDiffText(text)
    }

    private func applyTextLabels(for kind: ExternalDiffKind) {
        switch kind {
        case .workingCopy:
            leftLabel = "BASE"
            rightLabel = "工作副本"
        case .revision(let revision, _, let action):
            leftLabel = DiffAssetLoader.revisionLeftLabel(
                revision: revision,
                action: action,
                hasContent: true
            )
            rightLabel = DiffAssetLoader.revisionRightLabel(
                revision: revision,
                action: action,
                hasContent: true
            )
        }
    }

    private func applyDiffText(_ text: String) {
        lines = UnifiedDiffParser.parse(text)
        sideBySideRows = SideBySideDiffBuilder.build(from: lines)
        isEmpty = sideBySideRows.filter {
            $0.leftHighlight != .empty || $0.rightHighlight != .empty
                || $0.leftText != nil || $0.rightText != nil
        }.isEmpty
    }

    private static func isBinaryDiffMessage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("binary") || lower.contains("cannot display")
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

    private func makeClient(for workingCopy: WorkingCopy) throws -> SvnClient {
        if let authStore {
            return try authStore.makeClient(forRepositoryURL: workingCopy.path)
        }
        return try SvnClient.detect()
    }

    @discardableResult
    private func handleAuthFailure(
        _ error: SvnError,
        workingCopy: WorkingCopy,
        retry: @escaping () async -> Void
    ) -> Bool {
        guard let authStore else { return false }
        let prompt = authStore.shouldPrompt(for: error, repositoryURL: workingCopy.path)
        guard prompt.needsPrompt else { return false }
        authStore.presentAuthPrompt(
            repositoryURL: workingCopy.path,
            needsCertTrust: prompt.needsCertTrust,
            retry: retry
        )
        return true
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
