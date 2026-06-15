import AppKit
import Foundation
import SvnKit

/// 仓库浏览器：懒加载目录树、远程 CRUD、文件预览与日志。
@MainActor
final class RepoBrowserViewModel: ObservableObject {

    @Published private(set) var rootURL = ""
    @Published var currentURL = ""
    @Published var revision = ""
    @Published var useRevision = false
    @Published var selectedURL: String?
    @Published private(set) var selectedKind: SvnListEntry.Kind?
    @Published private(set) var listItems: [RepoTreeNode] = []
    @Published private(set) var treeChildren: [String: [RepoTreeNode]] = [:]
    @Published var expandedURLs: Set<String> = []
    @Published private(set) var fileContent: String?
    @Published private(set) var fileIsBinary = false
    @Published private(set) var logEntries: [SvnLogEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingPreview = false
    @Published var errorMessage: String?
    @Published private(set) var operationMessage: String?

    private weak var authStore: AuthSettingsStore?
    private var repositoryRoot = ""

    var selectedNode: RepoTreeNode? {
        guard let selectedURL else { return nil }
        if selectedURL == rootURL {
            return RepoTreeNode(rootURL: rootURL)
        }
        return findNode(url: selectedURL)
    }

    var selectedIsDirectory: Bool {
        if selectedURL == rootURL { return true }
        if let selectedKind { return selectedKind == .dir }
        return selectedNode?.kind == .dir
    }

    var selectedFileName: String? {
        guard let selectedURL, !selectedIsDirectory else { return nil }
        return RepositoryURLHelper.lastComponent(of: selectedURL)
    }

    var revisionArgument: String? {
        guard useRevision else { return nil }
        let trimmed = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var rootURLPrefix: String {
        rootURL.hasSuffix("/") ? String(rootURL.dropLast()) : rootURL
    }

    private var navigationAnchorForUp: String {
        if !selectedIsDirectory, let selectedURL { return selectedURL }
        return currentURL
    }

    var goUpTarget: String? {
        RepositoryURLHelper.parentURL(of: navigationAnchorForUp)
    }

    var canGoUp: Bool {
        guard let parent = goUpTarget else { return false }
        let root = rootURLPrefix
        return parent == root || (parent.count >= root.count && parent.hasPrefix(root))
    }

    func configure(authStore: AuthSettingsStore) {
        self.authStore = authStore
    }

    func copyRemoteURL(_ url: String) {
        let text: String
        if let rev = revisionArgument {
            text = "\(url)@\(rev)"
        } else {
            text = url
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        operationMessage = "已复制远程链接"
    }

    func load(workingCopy: WorkingCopy) async {
        errorMessage = nil
        do {
            let client = try makeClient(for: workingCopy)
            let info = try await client.info(at: workingCopy.directoryURL)
            rootURL = info.url
            repositoryRoot = info.repositoryRoot
            currentURL = info.url
            selectedURL = info.url
            selectedKind = .dir
            expandedURLs = [info.url]
            treeChildren = [:]
            await loadDirectory(info.url)
        } catch let error as SvnError {
            if !handleAuthFailure(error, workingCopy: workingCopy, retry: { [weak self] in
                await self?.load(workingCopy: workingCopy)
            }) {
                errorMessage = error.message
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard !currentURL.isEmpty else { return }
        treeChildren = [:]
        expandedURLs = [rootURL]
        await loadDirectory(currentURL)
        if let selectedURL, selectedURL != currentURL {
            if selectedIsDirectory {
                await loadDirectory(selectedURL)
            } else {
                await loadFilePreview(url: selectedURL)
            }
        }
    }

    func select(_ url: String) async {
        let kind = resolveKind(for: url)
        selectedURL = url
        selectedKind = kind

        if url == rootURL || kind == .dir {
            currentURL = url
            await loadDirectory(url)
            fileContent = nil
            logEntries = []
        } else {
            await loadFilePreview(url: url)
            await loadFileLog(url: url)
        }
    }

    /// 延迟到下一 runloop，避免 List selection 回调内重入刷新 NSTableView。
    func selectDeferred(_ url: String) {
        DispatchQueue.main.async {
            Task { await self.select(url) }
        }
    }

    func goUp() async {
        guard let parent = goUpTarget, canGoUp else { return }
        expandedURLs.insert(parent)
        await select(parent)
    }

    func goUpDeferred() {
        DispatchQueue.main.async {
            Task { await self.goUp() }
        }
    }

    func toggleExpand(_ url: String) async {
        if expandedURLs.contains(url) {
            expandedURLs.remove(url)
        } else {
            expandedURLs.insert(url)
            if treeChildren[url] == nil {
                await loadTreeChildren(parentURL: url)
            }
        }
    }

    func toggleExpandDeferred(_ url: String, expanded: Bool) {
        DispatchQueue.main.async {
            Task {
                if expanded {
                    if !self.expandedURLs.contains(url) {
                        self.expandedURLs.insert(url)
                        if self.treeChildren[url] == nil {
                            await self.loadTreeChildren(parentURL: url)
                        }
                    }
                } else {
                    self.expandedURLs.remove(url)
                }
            }
        }
    }

    func loadTreeChildren(parentURL: String) async {
        do {
            let client = try makeClient()
            let entries = try await client.list(parentURL, revision: revisionArgument)
            let children = entries
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { RepoTreeNode(entry: $0, parentURL: parentURL) }
            treeChildren[parentURL] = children
        } catch {
            treeChildren[parentURL] = []
        }
    }

    func createFolder(name: String, message: String, workingCopy: WorkingCopy) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = selectedURL ?? currentURL
        guard !trimmed.isEmpty, !parent.isEmpty else { return false }
        let target = RepositoryURLHelper.childURL(parent: parent, name: trimmed)
        return await perform(workingCopy: workingCopy) { client in
            try await client.mkdir(target, message: message, parents: true)
            return "已创建目录 \(trimmed)"
        } onSuccess: { [weak self] in
            await self?.reloadAfterRemoteChange(at: parent)
        }
    }

    func deleteSelected(message: String, workingCopy: WorkingCopy) async -> Bool {
        guard let url = selectedURL, url != rootURL else { return false }
        let parent = RepositoryURLHelper.parentURL(of: url) ?? rootURL
        return await perform(workingCopy: workingCopy) { client in
            try await client.deleteRemote(url, message: message)
            return "已删除 \(RepositoryURLHelper.lastComponent(of: url))"
        } onSuccess: { [weak self] in
            self?.selectedURL = parent
            self?.currentURL = parent
            await self?.reloadAfterRemoteChange(at: parent)
        }
    }

    func renameSelected(to newName: String, message: String, workingCopy: WorkingCopy) async -> Bool {
        guard let url = selectedURL, url != rootURL else { return false }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parent = RepositoryURLHelper.parentURL(of: url) ?? rootURL
        let dest = RepositoryURLHelper.childURL(parent: parent, name: trimmed)
        return await perform(workingCopy: workingCopy) { client in
            try await client.moveRemote(from: url, to: dest, message: message)
            return "已重命名为 \(trimmed)"
        } onSuccess: { [weak self] in
            self?.selectedURL = dest
            await self?.reloadAfterRemoteChange(at: parent)
        }
    }

    func exportSelected(to destination: URL, workingCopy: WorkingCopy) async -> Bool {
        guard let url = selectedURL, !selectedIsDirectory else { return false }
        return await perform(workingCopy: workingCopy) { client in
            try await client.export(url, to: destination, revision: self.revisionArgument)
            return "已导出到 \(destination.path)"
        }
    }

    // MARK: - Private

    private func loadDirectory(_ url: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = try makeClient()
            let entries = try await client.list(url, revision: revisionArgument)
            listItems = entries
                .sorted { lhs, rhs in
                    if lhs.kind != rhs.kind {
                        return lhs.kind == .dir
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                .map { RepoTreeNode(entry: $0, parentURL: url) }
            treeChildren[url] = listItems
        } catch let error as SvnError {
            listItems = []
            errorMessage = error.message
        } catch {
            listItems = []
            errorMessage = error.localizedDescription
        }
    }

    private func loadFilePreview(url: String) async {
        isLoadingPreview = true
        fileContent = nil
        fileIsBinary = false
        defer { isLoadingPreview = false }

        do {
            let client = try makeClient()
            let data = try await client.cat(url, revision: revisionArgument)
            if let text = String(data: data, encoding: .utf8), data.count < 512_000 {
                fileContent = text
            } else {
                fileIsBinary = true
                fileContent = "（二进制或过大文件，共 \(data.count) 字节，请使用导出）"
            }
        } catch {
            fileContent = nil
            errorMessage = error.localizedDescription
        }
    }

    private func loadFileLog(url: String) async {
        do {
            let client = try makeClient()
            logEntries = try await client.log(at: url, limit: 30, revisionRange: "HEAD:1", verbose: false)
        } catch {
            logEntries = []
        }
    }

    private func reloadAfterRemoteChange(at parent: String) async {
        treeChildren = [:]
        expandedURLs.insert(parent)
        await loadDirectory(parent)
        await loadTreeChildren(parentURL: parent)
        if let parentParent = RepositoryURLHelper.parentURL(of: parent) {
            await loadTreeChildren(parentURL: parentParent)
        }
    }

    private func findNode(url: String) -> RepoTreeNode? {
        for children in treeChildren.values {
            if let match = children.first(where: { $0.url == url }) {
                return match
            }
        }
        return listItems.first { $0.url == url }
    }

    private func resolveKind(for url: String) -> SvnListEntry.Kind {
        if url == rootURL { return .dir }
        if let node = findNode(url: url) { return node.kind }
        return .file
    }

    @discardableResult
    private func perform(
        workingCopy: WorkingCopy,
        _ operation: (SvnClient) async throws -> String,
        onSuccess: (() async -> Void)? = nil
    ) async -> Bool {
        isLoading = true
        operationMessage = nil
        defer { isLoading = false }

        do {
            let client = try makeClient(for: workingCopy)
            operationMessage = try await operation(client)
            await onSuccess?()
            return true
        } catch let error as SvnError {
            if !handleAuthFailure(error, workingCopy: workingCopy, retry: {}) {
                errorMessage = error.message
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func makeClient(for workingCopy: WorkingCopy? = nil) throws -> SvnClient {
        if let workingCopy, let authStore {
            return try authStore.makeClient(forRepositoryURL: workingCopy.path)
        }
        if let authStore, !repositoryRoot.isEmpty {
            return try authStore.makeClient(forRepositoryURL: repositoryRoot)
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
}
