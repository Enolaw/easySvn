import Foundation
import SwiftUI
import SvnKit

/// 工作副本状态视图的数据加载与操作（update / commit / revert / add）。
@MainActor
final class StatusViewModel: ObservableObject {

    private static let recentMessagesKey = "recentCommitMessages"
    private static let maxRecentMessages = 10

    @Published private(set) var info: SvnInfo?
    @Published private(set) var entries: [SvnStatusEntry] = []
    @Published private(set) var isLoading = false
    /// 整页错误（目录不是工作副本等，状态加载失败）。
    @Published private(set) var errorMessage: String?
    /// 单次操作失败（弹窗展示，不影响列表）。
    @Published var operationError: String?
    /// 最近一次操作的成功提示（如"已提交 r6"）。
    @Published private(set) var operationMessage: String?
    /// 提交勾选的文件路径。
    @Published var selectedPaths: Set<String> = []
    /// 最近提交日志（供提交面板快速复用）。
    @Published private(set) var recentCommitMessages: [String]

    init() {
        recentCommitMessages = UserDefaults.standard.stringArray(forKey: Self.recentMessagesKey) ?? []
    }

    /// 可纳入提交的状态。
    static func isCommittable(_ status: SvnItemStatus) -> Bool {
        switch status {
        case .modified, .added, .deleted, .replaced: true
        default: false
        }
    }

    var committableEntries: [SvnStatusEntry] {
        entries.filter { Self.isCommittable($0.itemStatus) }
    }

    // MARK: - 状态加载

    func refresh(workingCopy: WorkingCopy) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = try SvnClient.detect()
            async let info = client.info(at: workingCopy.directoryURL)
            async let entries = client.status(at: workingCopy.directoryURL)
            self.info = try await info
            self.entries = (try await entries).sorted { $0.path < $1.path }
            // 默认勾选全部可提交项（与 TortoiseSVN 提交对话框一致）
            selectedPaths = Set(committableEntries.map(\.path))
        } catch {
            info = nil
            entries = []
            selectedPaths = []
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    // MARK: - 操作

    func update(workingCopy: WorkingCopy) async {
        await perform(workingCopy: workingCopy) { client in
            let revision = try await client.update(at: workingCopy.directoryURL)
            return revision.map { "已更新到 r\($0)" } ?? "更新完成"
        }
    }

    /// 提交勾选的文件，成功返回 true（供提交面板关闭）。
    func commit(workingCopy: WorkingCopy, message: String) async -> Bool {
        let paths = selectedPaths.sorted()
        guard !paths.isEmpty else { return false }
        return await perform(workingCopy: workingCopy) { client in
            let revision = try await client.commit(paths: paths, message: message, in: workingCopy.directoryURL)
            self.rememberCommitMessage(message)
            return revision.map { "已提交 r\($0)（\(paths.count) 个文件）" } ?? "提交完成"
        }
    }

    func revert(workingCopy: WorkingCopy, paths: [String]) async {
        await perform(workingCopy: workingCopy) { client in
            try await client.revert(paths: paths, in: workingCopy.directoryURL)
            return "已还原 \(paths.count) 个文件"
        }
    }

    func addToVersionControl(workingCopy: WorkingCopy, paths: [String]) async {
        await perform(workingCopy: workingCopy) { client in
            try await client.add(paths: paths, in: workingCopy.directoryURL)
            return "已加入版本控制"
        }
    }

    /// 统一的操作执行：忙碌状态、错误弹窗、成功提示、完成后刷新。
    @discardableResult
    private func perform(
        workingCopy: WorkingCopy,
        _ operation: (SvnClient) async throws -> String
    ) async -> Bool {
        isLoading = true
        operationMessage = nil
        defer { isLoading = false }

        do {
            let client = try SvnClient.detect()
            let message = try await operation(client)
            await refresh(workingCopy: workingCopy)
            operationMessage = message
            return true
        } catch {
            operationError = Self.friendlyMessage(for: error)
            return false
        }
    }

    private func rememberCommitMessage(_ message: String) {
        var messages = recentCommitMessages.filter { $0 != message }
        messages.insert(message, at: 0)
        recentCommitMessages = Array(messages.prefix(Self.maxRecentMessages))
        UserDefaults.standard.set(recentCommitMessages, forKey: Self.recentMessagesKey)
    }

    // MARK: - 错误文案

    private static func friendlyMessage(for error: Error) -> String {
        if let svnError = error as? SvnError {
            switch svnError.code {
            case SvnError.Code.notAWorkingCopy:
                return "该目录不是 SVN 工作副本"
            case SvnError.Code.workingCopyLocked:
                return "工作副本被锁定，请执行 Cleanup 后重试"
            case SvnError.Code.authnFailed:
                return "认证失败，请检查用户名和密码"
            default:
                return svnError.message
            }
        }
        if case SvnKitError.svnNotFound = error {
            return "找不到 svn 命令行工具，请先安装：brew install subversion"
        }
        return error.localizedDescription
    }
}
