import Foundation
import SwiftUI
import SvnKit

/// 变更列表排序方式。
enum StatusSortOrder: String, CaseIterable, Identifiable {
    case path
    case status

    var id: String { rawValue }

    var label: String {
        switch self {
        case .path: "路径"
        case .status: "状态"
        }
    }
}

/// 工作副本状态视图的数据加载与操作（update / commit / revert / add）。
@MainActor
final class StatusViewModel: ObservableObject {

    private static let recentMessagesKey = "recentCommitMessages"
    private static let maxRecentMessages = 10

    @Published private(set) var info: SvnInfo?
    @Published private(set) var entries: [SvnStatusEntry] = []
    @Published var sortOrder: StatusSortOrder = .status
    @Published private(set) var isLoading = false
    /// 整页错误（目录不是工作副本等，状态加载失败）。
    @Published private(set) var errorMessage: String?
    /// 单次操作失败（弹窗展示，不影响列表）。
    @Published var operationError: String?
    /// 最近一次操作的成功提示（如"已提交 r6"）。
    @Published private(set) var operationMessage: String?
    /// 勾选的路径（可提交 / 未版本控制 / 缺失）。
    @Published var selectedPaths: Set<String> = []
    /// 最近提交日志（供提交面板快速复用）。
    @Published private(set) var recentCommitMessages: [String]

    init() {
        recentCommitMessages = UserDefaults.standard.stringArray(forKey: Self.recentMessagesKey) ?? []
    }

    /// 排序后的变更列表。
    var sortedEntries: [SvnStatusEntry] {
        switch sortOrder {
        case .path:
            return entries.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
        case .status:
            return entries.sorted {
                let priority0 = $0.itemStatus.sortPriority
                let priority1 = $1.itemStatus.sortPriority
                if priority0 != priority1 { return priority0 < priority1 }
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
        }
    }

    /// 树形变更列表（按目录层级组织）。
    var statusTree: [StatusTreeNode] {
        StatusTreeBuilder.build(from: sortedEntries, sortOrder: sortOrder)
    }

    /// 可纳入提交的状态。
    static func isCommittable(_ status: SvnItemStatus) -> Bool {
        switch status {
        case .modified, .added, .deleted, .replaced: true
        default: false
        }
    }

    /// 列表中可勾选的状态。
    static func isSelectable(_ status: SvnItemStatus) -> Bool {
        isCommittable(status) || status == .unversioned || status == .missing
    }

    var committableEntries: [SvnStatusEntry] {
        entries.filter { Self.isCommittable($0.itemStatus) }
    }

    var selectedCommittablePaths: [String] {
        entries
            .filter { selectedPaths.contains($0.path) && Self.isCommittable($0.itemStatus) }
            .map(\.path)
    }

    var selectedUnversionedPaths: [String] {
        entries
            .filter { selectedPaths.contains($0.path) && $0.itemStatus == .unversioned }
            .map(\.path)
    }

    var selectedMissingPaths: [String] {
        entries
            .filter { selectedPaths.contains($0.path) && $0.itemStatus == .missing }
            .map(\.path)
    }

    // MARK: - 勾选（文件夹联动子项）

    /// 勾选/取消某路径；若为文件夹则同步其下所有可勾选项。
    func setPathSelected(_ path: String, isOn: Bool) {
        let subtree = selectablePaths(inSubtreeOf: path)
        if isOn {
            selectedPaths.formUnion(subtree)
        } else {
            selectedPaths.subtract(subtree)
            // 取消子项时，同步取消所有祖先文件夹的勾选
            selectedPaths.subtract(ancestorPaths(of: path))
        }
    }

    /// 路径在列表中是否有子项（视为文件夹）。
    func hasSelectableDescendants(_ path: String) -> Bool {
        entries.contains { entry in
            Self.isSelectable(entry.itemStatus)
                && entry.path != path
                && entry.path.hasPrefix(path + "/")
        }
    }

    /// 该路径子树内是否有可勾选项。
    func hasSelectableContent(at path: String) -> Bool {
        !selectablePaths(inSubtreeOf: path).isEmpty
    }

    /// 该路径子树内可勾选项是否已全部勾选。
    func isPathFullySelected(_ path: String) -> Bool {
        let subtree = selectablePaths(inSubtreeOf: path)
        return !subtree.isEmpty && subtree.isSubset(of: selectedPaths)
    }

    func entry(at path: String) -> SvnStatusEntry? {
        entries.first { $0.path == path }
    }

    /// 某路径及其下所有可勾选项。
    private func selectablePaths(inSubtreeOf root: String) -> Set<String> {
        Set(
            entries
                .filter { entry in
                    Self.isSelectable(entry.itemStatus)
                        && (entry.path == root || entry.path.hasPrefix(root + "/"))
                }
                .map(\.path)
        )
    }

    /// 某路径的所有祖先目录路径。
    private func ancestorPaths(of path: String) -> Set<String> {
        var ancestors = Set<String>()
        var current = path
        while let slash = current.lastIndex(of: "/") {
            current = String(current[..<slash])
            ancestors.insert(current)
        }
        return ancestors
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
            self.entries = try await entries
            // 默认勾选全部可提交项（与 TortoiseSVN 提交对话框一致）
            selectedPaths = Set(committableEntries.map(\.path))
        } catch {
            info = nil
            entries = []
            selectedPaths = []
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    func selectAllSelectable() {
        selectedPaths = selectablePathSet
    }

    func deselectAll() {
        selectedPaths = []
    }

    /// 是否已勾选全部可选项。
    var allSelectableSelected: Bool {
        let selectable = selectablePathSet
        return !selectable.isEmpty && selectable.isSubset(of: selectedPaths)
    }

    private var selectablePathSet: Set<String> {
        Set(entries.filter { Self.isSelectable($0.itemStatus) }.map(\.path))
    }

    // MARK: - 操作

    func update(workingCopy: WorkingCopy) async {
        await perform(workingCopy: workingCopy) { client in
            let revision = try await client.update(at: workingCopy.directoryURL)
            return revision.map { "已更新到 r\($0)" } ?? "更新完成"
        }
    }

    /// 从仓库恢复缺失的文件/目录。
    func restoreMissing(workingCopy: WorkingCopy, paths: [String]) async {
        guard !paths.isEmpty else { return }
        await perform(workingCopy: workingCopy) { client in
            _ = try await client.update(at: workingCopy.directoryURL, paths: paths)
            return "已从仓库恢复 \(paths.count) 个缺失项"
        }
    }

    /// 将缺失项标记为删除，并勾选以便提交。
    @discardableResult
    func scheduleDeletionForMissing(workingCopy: WorkingCopy, paths: [String]) async -> Bool {
        guard !paths.isEmpty else { return false }
        isLoading = true
        operationMessage = nil
        defer { isLoading = false }

        do {
            let client = try SvnClient.detect()
            try await client.delete(paths: paths, in: workingCopy.directoryURL)
            await refresh(workingCopy: workingCopy)
            selectedPaths = Set(
                entries
                    .filter { paths.contains($0.path) && Self.isCommittable($0.itemStatus) }
                    .map(\.path)
            )
            operationMessage = "已标记 \(paths.count) 个缺失项为删除，请提交"
            return !selectedPaths.isEmpty
        } catch {
            operationError = Self.friendlyMessage(for: error)
            return false
        }
    }

    /// 提交勾选的文件，成功返回 true（供提交面板关闭）。
    func commit(workingCopy: WorkingCopy, message: String) async -> Bool {
        let paths = selectedCommittablePaths
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
        guard !paths.isEmpty else { return }
        await perform(workingCopy: workingCopy) { client in
            try await client.add(paths: paths, in: workingCopy.directoryURL)
            return "已加入版本控制 \(paths.count) 个文件"
        }
    }

    /// 加入版本控制并勾选，供打开提交面板。
    @discardableResult
    func addUnversionedAndPrepareCommit(workingCopy: WorkingCopy, paths: [String]) async -> Bool {
        guard !paths.isEmpty else { return false }
        isLoading = true
        operationMessage = nil
        defer { isLoading = false }

        do {
            let client = try SvnClient.detect()
            try await client.add(paths: paths, in: workingCopy.directoryURL)
            await refresh(workingCopy: workingCopy)
            selectedPaths = Set(
                entries
                    .filter { paths.contains($0.path) && Self.isCommittable($0.itemStatus) }
                    .map(\.path)
            )
            operationMessage = "已加入版本控制 \(paths.count) 个文件，请提交"
            return !selectedPaths.isEmpty
        } catch {
            operationError = Self.friendlyMessage(for: error)
            return false
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
