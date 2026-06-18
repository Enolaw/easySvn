import Foundation
import SwiftUI
import SvnKit

/// 选中项操作条摘要（勾选变化时单次遍历更新，避免列表重复计算）。
struct SelectionActionSummary: Equatable {
    var unversionedCount = 0
    var addedCount = 0
    var missingCount = 0
    var ignoredCount = 0

    var totalCount: Int { unversionedCount + addedCount + missingCount + ignoredCount }
    var hasActions: Bool { totalCount > 0 }

    var categoryCount: Int {
        [unversionedCount, addedCount, missingCount, ignoredCount].filter { $0 > 0 }.count
    }

    var summaryText: String {
        var parts: [String] = []
        if unversionedCount > 0 { parts.append("未版本控制 \(unversionedCount)") }
        if addedCount > 0 { parts.append("新增 \(addedCount)") }
        if missingCount > 0 { parts.append("缺失 \(missingCount)") }
        if ignoredCount > 0 { parts.append("已忽略 \(ignoredCount)") }
        if parts.count <= 1 {
            return "已选 \(totalCount) 项"
        }
        return "已选 \(totalCount) 项：" + parts.joined(separator: " · ")
    }
}

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
    @Published private(set) var statusTree: [StatusTreeNode] = []
    /// 随 `selectedPaths` / `entries` 更新，不单独触发刷新。
    private(set) var selectionSummary = SelectionActionSummary()
    @Published var sortOrder: StatusSortOrder = .status {
        didSet { rebuildDisplayState() }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage: String?
    /// 整页错误（目录不是工作副本等，状态加载失败）。
    @Published private(set) var errorMessage: String?
    /// 单次操作失败（弹窗展示，不影响列表）。
    @Published var operationError: String?
    /// 最近一次操作的成功提示（如"已提交 r6"）。
    @Published private(set) var operationMessage: String?
    /// 勾选的路径（可提交 / 未版本控制 / 缺失）。
    @Published var selectedPaths: Set<String> = [] {
        didSet { updateSelectionSummary() }
    }
    /// 仅显示冲突文件。
    @Published var showConflictsOnly = false {
        didSet { rebuildDisplayState() }
    }
    /// 最近提交日志（供提交面板快速复用）。
    @Published private(set) var recentCommitMessages: [String]

    private weak var authStore: AuthSettingsStore?
    private weak var appSettings: AppSettingsStore?
    private var refreshSession = UUID()
    private var refreshTask: Task<Void, Never>?
    private var watcherPausedUntil: Date?
    private var subtreeSelectableCache: [String: Set<String>] = [:]

    /// FSEvents 自动刷新是否应跳过（加载中或用户刚取消后冷却）。
    var shouldSkipWatcherRefresh: Bool {
        if isLoading { return true }
        if let until = watcherPausedUntil, Date() < until { return true }
        return false
    }

    init() {
        recentCommitMessages = AppUserDefaults.shared.stringArray(forKey: Self.recentMessagesKey) ?? []
    }

    func configure(authStore: AuthSettingsStore, appSettings: AppSettingsStore) {
        self.authStore = authStore
        self.appSettings = appSettings
    }

    /// 冲突条目（文本冲突或树冲突）。
    var conflictedEntries: [SvnStatusEntry] {
        entries.filter { Self.isConflicted($0) }
    }

    /// 列表展示用的条目（可按冲突过滤）。
    private var displayedEntries: [SvnStatusEntry] {
        if showConflictsOnly {
            return conflictedEntries
        }
        return entries
    }

    /// 排序后的变更列表。
    var sortedEntries: [SvnStatusEntry] {
        switch sortOrder {
        case .path:
            return displayedEntries.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
        case .status:
            return displayedEntries.sorted {
                let priority0 = $0.displayStatus.sortPriority
                let priority1 = $1.displayStatus.sortPriority
                if priority0 != priority1 { return priority0 < priority1 }
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
        }
    }

    static func isConflicted(_ entry: SvnStatusEntry) -> Bool {
        entry.itemStatus == .conflicted || entry.isTreeConflicted
    }

    /// 可纳入提交的状态（仅内容维度，属性变更请用 `SvnStatusEntry.isCommittable`）。
    static func isCommittable(_ status: SvnItemStatus) -> Bool {
        SvnStatusEntry.isCommittableItem(status)
    }

    /// 列表中可勾选的状态。
    static func isSelectable(_ entry: SvnStatusEntry) -> Bool {
        entry.isCommittable || entry.itemStatus == .unversioned || entry.itemStatus == .missing
            || entry.itemStatus == .ignored
    }

    var committableEntries: [SvnStatusEntry] {
        entries.filter(\.isCommittable)
    }

    var selectedCommittablePaths: [String] {
        entries
            .filter { selectedPaths.contains($0.path) && $0.isCommittable }
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

    var selectedAddedPaths: [String] {
        entries
            .filter { selectedPaths.contains($0.path) && $0.itemStatus == .added }
            .map(\.path)
    }

    var selectedIgnoredPaths: [String] {
        entries
            .filter { selectedPaths.contains($0.path) && $0.itemStatus == .ignored }
            .map(\.path)
    }

    /// 误 add 的 .venv 等巨型目录根路径（用于顶部提示条）。
    var massAddedVenvRoots: [String] {
        IgnorePathHelper.massAddedVenvRoots(
            in: entries.map { (path: $0.path, status: $0.itemStatus.rawValue) }
        )
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
            Self.isSelectable(entry)
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
        subtreeSelectableCache[root] ?? []
    }

    private func rebuildDisplayState() {
        statusTree = StatusTreeBuilder.build(from: sortedEntries, sortOrder: sortOrder)
        rebuildSubtreeCache()
        updateSelectionSummary()
    }

    private func rebuildSubtreeCache() {
        var cache: [String: Set<String>] = [:]
        for entry in entries where Self.isSelectable(entry) {
            var current = entry.path
            while true {
                cache[current, default: []].insert(entry.path)
                guard let slash = current.lastIndex(of: "/") else { break }
                current = String(current[..<slash])
            }
        }
        subtreeSelectableCache = cache
    }

    private func updateSelectionSummary() {
        var summary = SelectionActionSummary()
        for entry in entries where selectedPaths.contains(entry.path) {
            switch entry.itemStatus {
            case .unversioned: summary.unversionedCount += 1
            case .added: summary.addedCount += 1
            case .missing: summary.missingCount += 1
            case .ignored: summary.ignoredCount += 1
            default: break
            }
        }
        if summary != selectionSummary {
            selectionSummary = summary
        }
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

    /// 发起状态扫描（取消上一次未完成的扫描，同一时刻仅一个任务）。
    func requestRefresh(
        workingCopy: WorkingCopy,
        changedPaths: [String]? = nil,
        managesLoadingUI: Bool = true,
        preserveSelection: Bool = false
    ) {
        refreshTask?.cancel()
        let session = UUID()
        refreshSession = session
        refreshTask = Task {
            await runRefresh(
                session: session,
                workingCopy: workingCopy,
                changedPaths: changedPaths,
                managesLoadingUI: managesLoadingUI,
                preserveSelection: preserveSelection
            )
            if refreshSession == session {
                refreshTask = nil
            }
        }
    }

    /// 取消进行中的状态扫描并终止底层 svn 进程。
    func cancelRefresh() {
        refreshSession = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
        loadingMessage = nil
        watcherPausedUntil = Date().addingTimeInterval(2)
    }

    /// 供操作完成后 await 的内部刷新（不与 UI 扫描任务并发）。
    func refresh(
        workingCopy: WorkingCopy,
        changedPaths: [String]? = nil,
        managesLoadingUI: Bool = true,
        preserveSelection: Bool = false
    ) async {
        refreshTask?.cancel()
        await runRefresh(
            session: nil,
            workingCopy: workingCopy,
            changedPaths: changedPaths,
            managesLoadingUI: managesLoadingUI,
            preserveSelection: preserveSelection
        )
    }

    private func isActiveSession(_ session: UUID?) -> Bool {
        session == nil || refreshSession == session
    }

    private func runRefresh(
        session: UUID?,
        workingCopy: WorkingCopy,
        changedPaths: [String]? = nil,
        managesLoadingUI: Bool = true,
        preserveSelection: Bool = false
    ) async {
        let focusPaths = changedPaths?.filter { !$0.isEmpty }
        let isIncremental = !(focusPaths?.isEmpty ?? true) && !entries.isEmpty && errorMessage == nil

        if managesLoadingUI && !isIncremental {
            isLoading = true
            loadingMessage = "正在扫描变更…"
        }
        errorMessage = nil
        defer {
            if isActiveSession(session), managesLoadingUI, !isIncremental {
                isLoading = false
                loadingMessage = nil
            }
        }

        do {
            try Task.checkCancellation()
            guard isActiveSession(session) else { return }

            let client = try makeClient(repositoryURL: workingCopy.path)
            let includeIgnored = appSettings?.showIgnored ?? false
            if isIncremental, let focusPaths {
                let updated = try await client.status(
                    at: workingCopy.directoryURL,
                    paths: focusPaths,
                    includeIgnored: includeIgnored
                )
                try Task.checkCancellation()
                guard isActiveSession(session) else { return }
                mergeIncrementalStatus(updated, focusPaths: focusPaths, workingCopyRoot: workingCopy.directoryURL)
                return
            }

            let info = try await client.info(at: workingCopy.directoryURL)
            try Task.checkCancellation()
            guard isActiveSession(session) else { return }
            self.info = info

            let loadedEntries = try await client.status(
                at: workingCopy.directoryURL,
                includeIgnored: includeIgnored
            )
            try Task.checkCancellation()
            guard isActiveSession(session) else { return }
            applyLoadedEntries(loadedEntries, workingCopyRoot: workingCopy.directoryURL)
            if !preserveSelection {
                selectedPaths = Set(committableEntries.map(\.path))
            } else {
                updateSelectionSummary()
            }
        } catch is CancellationError {
            return
        } catch {
            guard isActiveSession(session) else { return }
            let repositoryURL = info?.repositoryRoot ?? info?.url ?? workingCopy.path
            if handleAuthFailure(error, repositoryURL: repositoryURL, retry: { [weak self] in
                self?.requestRefresh(workingCopy: workingCopy)
            }) {
                return
            }
            info = nil
            entries = []
            statusTree = []
            subtreeSelectableCache = [:]
            selectionSummary = SelectionActionSummary()
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
        Set(entries.filter { Self.isSelectable($0) }.map(\.path))
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
            let client = try makeClient(for: workingCopy)
            try await client.delete(paths: paths, in: workingCopy.directoryURL)
            await refresh(
                workingCopy: workingCopy,
                changedPaths: paths,
                managesLoadingUI: false,
                preserveSelection: true
            )
            selectedPaths = Set(
                entries
                    .filter { paths.contains($0.path) && $0.isCommittable }
                    .map(\.path)
            )
            operationMessage = "已标记 \(paths.count) 个缺失项为删除，请提交"
            return !selectedPaths.isEmpty
        } catch {
            let repositoryURL = info?.repositoryRoot ?? info?.url ?? workingCopy.path
            if handleAuthFailure(error, repositoryURL: repositoryURL, retry: { [weak self] in
                _ = await self?.scheduleDeletionForMissing(workingCopy: workingCopy, paths: paths)
            }) {
                return false
            }
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

    /// 取消已 schedule 的添加（`svn revert`，对目录递归）。
    func cancelScheduledAdd(workingCopy: WorkingCopy, paths: [String]) async {
        guard !paths.isEmpty else { return }
        let roots = IgnorePathHelper.collapseRevertRoots(paths: paths)
        await perform(workingCopy: workingCopy, loadingMessage: "正在取消添加…") { client in
            for root in roots {
                try await client.revert(
                    paths: [root],
                    recursive: self.shouldRevertRecursively(root: root, in: workingCopy),
                    in: workingCopy.directoryURL
                )
            }
            return "已取消 \(roots.count) 项的添加"
        }
    }

    /// 将路径加入父目录的 svn:ignore，并对已添加项执行 revert。
    func addToIgnoreList(workingCopy: WorkingCopy, paths: [String]) async {
        guard !paths.isEmpty else { return }
        var byParent: [String: Set<String>] = [:]
        for path in paths {
            if let spec = IgnorePathHelper.ignoreSpec(for: path) {
                byParent[spec.parent, default: []].insert(spec.pattern)
            }
        }
        guard !byParent.isEmpty else { return }

        let addedPaths = entries
            .filter { paths.contains($0.path) && $0.itemStatus == .added }
            .map(\.path)
        let revertRoots = IgnorePathHelper.collapseRevertRoots(paths: paths)

        await perform(workingCopy: workingCopy, loadingMessage: "正在加入忽略…") { client in
            for (parent, patterns) in byParent.sorted(by: { $0.key < $1.key }) {
                try await client.appendIgnore(
                    patterns: Array(patterns).sorted(),
                    at: parent,
                    in: workingCopy.directoryURL
                )
            }
            for root in revertRoots where addedPaths.contains(where: { $0 == root || $0.hasPrefix(root + "/") }) {
                try await client.revert(paths: [root], recursive: true, in: workingCopy.directoryURL)
            }
            let count = byParent.values.reduce(0) { $0 + $1.count }
            return "已将 \(count) 项加入 svn:ignore"
        }
    }

    /// 从父目录的 svn:ignore 中移除模式，使文件重新显示为未版本控制。
    func removeFromIgnoreList(workingCopy: WorkingCopy, paths: [String]) async {
        guard !paths.isEmpty else { return }
        var byParent: [String: Set<String>] = [:]
        for path in paths {
            if let spec = IgnorePathHelper.ignoreSpec(for: path) {
                byParent[spec.parent, default: []].insert(spec.pattern)
            }
        }
        guard !byParent.isEmpty else { return }

        await perform(workingCopy: workingCopy, loadingMessage: "正在取消忽略…") { client in
            for (parent, patterns) in byParent.sorted(by: { $0.key < $1.key }) {
                try await client.removeIgnore(
                    patterns: Array(patterns).sorted(),
                    at: parent,
                    in: workingCopy.directoryURL
                )
            }
            let count = byParent.values.reduce(0) { $0 + $1.count }
            return "已取消 \(count) 项的忽略"
        }
    }

    /// 取消 .venv 等待添加并写入 svn:ignore（一键修复误 add）。
    func fixMassAddedVenv(workingCopy: WorkingCopy, root: String) async {
        guard let spec = IgnorePathHelper.ignoreSpec(for: root) else { return }
        await perform(workingCopy: workingCopy, loadingMessage: "正在处理 \(spec.pattern)…") { client in
            try await client.revert(paths: [root], recursive: true, in: workingCopy.directoryURL)
            try await client.appendIgnore(
                patterns: [spec.pattern],
                at: spec.parent,
                in: workingCopy.directoryURL
            )
            return "已取消添加并将 \(spec.pattern) 加入忽略"
        }
    }

    private func shouldRevertRecursively(root: String, in workingCopy: WorkingCopy) -> Bool {
        var isDirectory: ObjCBool = false
        let url = workingCopy.directoryURL.appendingPathComponent(root)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return true
        }
        return isDirectory.boolValue
    }

    func resolveConflict(
        workingCopy: WorkingCopy,
        path: String,
        accept: SvnResolveAccept
    ) async {
        await perform(workingCopy: workingCopy) { client in
            try await client.resolve(paths: [path], accept: accept, in: workingCopy.directoryURL)
            return accept.displayName
        }
    }

    func markConflictResolved(workingCopy: WorkingCopy, path: String) async {
        await perform(workingCopy: workingCopy) { client in
            try await client.markResolved(paths: [path], in: workingCopy.directoryURL)
            return "已标记为已解决"
        }
    }

    func addToVersionControl(workingCopy: WorkingCopy, paths: [String]) async {
        let preparation = preparePathsForAdd(paths, workingCopy: workingCopy)
        guard let allowed = preparation.allowed else { return }
        await perform(workingCopy: workingCopy, loadingMessage: "正在加入版本控制…") { client in
            try await client.add(
                paths: allowed,
                force: true,
                in: workingCopy.directoryURL
            )
            return "已加入版本控制 \(allowed.count) 个文件"
        }
    }

    /// 加入版本控制并勾选，供打开提交面板。
    @discardableResult
    func addUnversionedAndPrepareCommit(workingCopy: WorkingCopy, paths: [String]) async -> Bool {
        let preparation = preparePathsForAdd(paths, workingCopy: workingCopy)
        guard let allowed = preparation.allowed else { return false }
        let skippedNote = preparation.skippedNote
        isLoading = true
        loadingMessage = "正在加入版本控制（\(allowed.count) 项）…"
        operationMessage = nil
        defer {
            isLoading = false
            loadingMessage = nil
        }

        do {
            let client = try makeClient(for: workingCopy)
            try await client.add(
                paths: allowed,
                force: true,
                in: workingCopy.directoryURL
            )
            await refresh(
                workingCopy: workingCopy,
                managesLoadingUI: false,
                preserveSelection: true
            )
            selectedPaths = Set(
                entries
                    .filter { allowed.contains($0.path) && $0.isCommittable }
                    .map(\.path)
            )
            var message = "已加入版本控制 \(allowed.count) 个文件，请提交"
            if let skippedNote {
                message += "\n\(skippedNote)"
            }
            operationMessage = message
            return !selectedPaths.isEmpty
        } catch {
            let repositoryURL = info?.repositoryRoot ?? info?.url ?? workingCopy.path
            if handleAuthFailure(error, repositoryURL: repositoryURL, retry: { [weak self] in
                _ = await self?.addUnversionedAndPrepareCommit(workingCopy: workingCopy, paths: paths)
            }) {
                return false
            }
            operationError = Self.friendlyMessage(for: error)
            return false
        }
    }

    private struct PreparedAddPaths {
        let allowed: [String]?
        let skippedNote: String?
    }

    private func preparePathsForAdd(
        _ paths: [String],
        workingCopy: WorkingCopy
    ) -> PreparedAddPaths {
        let unversionedInput = filterUnversionedPaths(paths)
        guard !unversionedInput.isEmpty else {
            operationError = "所选路径均已受版本控制，无需再次添加"
            return PreparedAddPaths(allowed: nil, skippedNote: nil)
        }

        let evaluation = UnversionedAddPolicy.evaluate(
            paths: unversionedInput,
            workingCopyRoot: workingCopy.directoryURL
        )
        var notes: [String] = []
        if !evaluation.redirected.isEmpty {
            notes.append(UnversionedAddPolicy.formatRedirectedSummary(redirected: evaluation.redirected))
        }
        if !evaluation.rejected.isEmpty {
            notes.append(UnversionedAddPolicy.formatRejectedSummary(
                title: "已跳过 \(evaluation.rejected.count) 项",
                rejected: evaluation.rejected
            ))
        }
        let skippedNote = notes.isEmpty ? nil : notes.joined(separator: "\n\n")
        if !evaluation.rejected.isEmpty && evaluation.allowed.isEmpty {
            operationError = UnversionedAddPolicy.formatRejectedSummary(
                title: "未执行添加",
                rejected: evaluation.rejected
            )
            return PreparedAddPaths(allowed: nil, skippedNote: skippedNote)
        }

        let allowed = resolveUnversionedAddTargets(
            from: evaluation.allowed,
            workingCopyRoot: workingCopy.directoryURL
        )
        if allowed.isEmpty {
            operationError = "所选路径均已受版本控制，无需再次添加"
            return PreparedAddPaths(allowed: nil, skippedNote: skippedNote)
        }
        return PreparedAddPaths(allowed: allowed, skippedNote: skippedNote)
    }

    /// 仅保留当前状态列表中标记为未版本控制的路径。
    private func filterUnversionedPaths(_ paths: [String]) -> [String] {
        let unversionedSet = Set(entries.filter { $0.itemStatus == .unversioned }.map(\.path))
        return paths.filter { unversionedSet.contains($0) }
    }

    /// 将目录路径展开为未版本控制叶子项；若仍为目录则保留目录路径供 `--force` 添加。
    private func resolveUnversionedAddTargets(
        from paths: [String],
        workingCopyRoot: URL
    ) -> [String] {
        let unversionedPaths = entries.filter { $0.itemStatus == .unversioned }.map(\.path)
        var resolved: [String] = []

        for path in paths {
            if unversionedPaths.contains(path) {
                resolved.append(path)
                continue
            }
            let descendants = unversionedPaths.filter { $0.hasPrefix(path + "/") }
            if !descendants.isEmpty {
                resolved.append(contentsOf: descendants)
            } else if isDirectoryPath(path, workingCopyRoot: workingCopyRoot) {
                resolved.append(path)
            }
        }
        return Array(Set(resolved)).sorted()
    }

    private func isDirectoryPath(_ path: String, workingCopyRoot: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let url = workingCopyRoot.appendingPathComponent(path).standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// 统一的操作执行：忙碌状态、错误弹窗、成功提示、完成后刷新。
    @discardableResult
    private func perform(
        workingCopy: WorkingCopy,
        loadingMessage: String? = nil,
        _ operation: @escaping (SvnClient) async throws -> String
    ) async -> Bool {
        isLoading = true
        self.loadingMessage = loadingMessage
        operationMessage = nil
        defer {
            isLoading = false
            self.loadingMessage = nil
        }

        do {
            let client = try makeClient(for: workingCopy)
            let message = try await operation(client)
            await refresh(workingCopy: workingCopy, managesLoadingUI: false)
            operationMessage = message
            return true
        } catch {
            let repositoryURL = info?.repositoryRoot ?? info?.url ?? workingCopy.path
            if handleAuthFailure(error, repositoryURL: repositoryURL, retry: { [weak self] in
                _ = await self?.perform(workingCopy: workingCopy, loadingMessage: loadingMessage, operation)
            }) {
                return false
            }
            operationError = Self.friendlyMessage(for: error)
            return false
        }
    }

    private func makeClient(for workingCopy: WorkingCopy) throws -> SvnClient {
        if let info {
            return try makeClient(forInfo: info)
        }
        return try makeClient(repositoryURL: workingCopy.path)
    }

    private func makeClient(forInfo info: SvnInfo) throws -> SvnClient {
        if let authStore {
            return try authStore.makeClient(forInfo: info)
        }
        return try SvnClient.detect()
    }

    private func makeClient(repositoryURL: String) throws -> SvnClient {
        if let authStore {
            return try authStore.makeClient(forRepositoryURL: repositoryURL)
        }
        return try SvnClient.detect()
    }

    @discardableResult
    private func handleAuthFailure(
        _ error: Error,
        repositoryURL: String,
        retry: @escaping () async -> Void
    ) -> Bool {
        guard let authStore else { return false }
        let prompt = authStore.shouldPrompt(for: error, repositoryURL: repositoryURL)
        guard prompt.needsPrompt else { return false }
        authStore.presentAuthPrompt(
            repositoryURL: repositoryURL,
            needsCertTrust: prompt.needsCertTrust,
            retry: retry
        )
        return true
    }

    private func applyLoadedEntries(_ loadedEntries: [SvnStatusEntry], workingCopyRoot: URL) {
        entries = UnversionedDirectoryExpander.expand(loadedEntries, workingCopyRoot: workingCopyRoot)
        rebuildDisplayState()
    }

    private func mergeIncrementalStatus(
        _ updated: [SvnStatusEntry],
        focusPaths: [String],
        workingCopyRoot: URL
    ) {
        var affected = Set(focusPaths)
        affected.formUnion(updated.map(\.path))
        entries.removeAll { affected.contains($0.path) }
        entries.append(contentsOf: updated)
        entries = UnversionedDirectoryExpander.expand(entries, workingCopyRoot: workingCopyRoot)
        rebuildDisplayState()
    }

    private func rememberCommitMessage(_ message: String) {
        var messages = recentCommitMessages.filter { $0 != message }
        messages.insert(message, at: 0)
        recentCommitMessages = Array(messages.prefix(Self.maxRecentMessages))
        AppUserDefaults.shared.set(recentCommitMessages, forKey: Self.recentMessagesKey)
    }

    // MARK: - 错误文案

    private static func friendlyMessage(for error: Error) -> String {
        if case ProcessRunnerError.timedOut(let seconds) = error {
            return """
            状态扫描超时（\(Int(seconds)) 秒）。工作副本可能过大，常见于误将 .venv、node_modules 加入版本控制。\
            可在终端对该目录执行 svn status / svn revert -R .venv 后重试。
            """
        }
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
