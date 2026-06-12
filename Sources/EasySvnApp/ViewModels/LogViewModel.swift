import AppKit
import Foundation
import SvnKit

/// 提交日志查看器数据。
@MainActor
final class LogViewModel: ObservableObject {

    private static let pageSize = 50

    @Published private(set) var entries: [SvnLogEntry] = []
    @Published var selectedRevision: Int?
    @Published var searchText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMore = true
    @Published private(set) var isServingFromCache = false

    private var oldestLoadedRevision: Int?
    private var repositoryKey = ""
    private weak var authStore: AuthSettingsStore?

    func configure(authStore: AuthSettingsStore) {
        self.authStore = authStore
    }

    var filteredEntries: [SvnLogEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return entries }
        return entries.filter {
            ($0.author?.localizedCaseInsensitiveContains(keyword) ?? false)
                || $0.message.localizedCaseInsensitiveContains(keyword)
                || String($0.revision).contains(keyword)
        }
    }

    var selectedEntry: SvnLogEntry? {
        guard let revision = selectedRevision else { return nil }
        return entries.first { $0.revision == revision }
    }

    func load(workingCopy: WorkingCopy, forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        hasMore = true
        isServingFromCache = false
        defer { isLoading = false }

        do {
            let client = try makeClient(for: workingCopy)
            let info = try? await client.info(at: workingCopy.directoryURL)
            repositoryKey = LogCacheStore.repositoryKey(for: workingCopy, info: info)

            if forceRefresh {
                await LogCacheStore.shared.invalidate(repositoryKey: repositoryKey)
            }

            let cacheKey = LogCacheKey(
                repositoryKey: repositoryKey,
                revisionRange: "HEAD:1",
                limit: Self.pageSize,
                verbose: true
            )

            if !forceRefresh, let cached = await LogCacheStore.shared.load(key: cacheKey) {
                applyLoaded(cached)
                isServingFromCache = true
            }

            let loaded = try await client.log(
                at: workingCopy.path,
                limit: Self.pageSize,
                revisionRange: "HEAD:1",
                verbose: true
            )
            applyLoaded(loaded)
            isServingFromCache = false
            await LogCacheStore.shared.store(key: cacheKey, entries: loaded)
        } catch let error as SvnError {
            if entries.isEmpty {
                if !handleAuthFailure(error, workingCopy: workingCopy, retry: { [weak self] in
                    await self?.load(workingCopy: workingCopy, forceRefresh: forceRefresh)
                }) {
                    errorMessage = error.message
                }
            }
        } catch SvnKitError.svnNotFound {
            if entries.isEmpty {
                errorMessage = "找不到 svn 命令行工具"
            }
        } catch {
            if entries.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore(workingCopy: WorkingCopy) async {
        guard hasMore, let oldest = oldestLoadedRevision, oldest > 1, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let client = try makeClient(for: workingCopy)
            let end = oldest - 1
            let range = "\(end):1"
            let cacheKey = LogCacheKey(
                repositoryKey: repositoryKey,
                revisionRange: range,
                limit: Self.pageSize,
                verbose: true
            )

            if let cached = await LogCacheStore.shared.load(key: cacheKey) {
                appendUnique(cached)
                oldestLoadedRevision = entries.last?.revision
                hasMore = (oldestLoadedRevision ?? 1) > 1
            }

            let loaded = try await client.log(
                at: workingCopy.path,
                limit: Self.pageSize,
                revisionRange: range,
                verbose: true
            )
            appendUnique(loaded)
            oldestLoadedRevision = entries.last?.revision
            hasMore = (oldestLoadedRevision ?? 1) > 1
            await LogCacheStore.shared.store(key: cacheKey, entries: loaded)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyRevision(_ revision: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(revision), forType: .string)
    }

    private func applyLoaded(_ loaded: [SvnLogEntry]) {
        entries = loaded
        oldestLoadedRevision = loaded.last?.revision
        if selectedRevision == nil {
            selectedRevision = loaded.first?.revision
        }
        hasMore = (oldestLoadedRevision ?? 1) > 1
    }

    private func appendUnique(_ loaded: [SvnLogEntry]) {
        let existing = Set(entries.map(\.revision))
        let newOnes = loaded.filter { !existing.contains($0.revision) }
        entries.append(contentsOf: newOnes)
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
}
