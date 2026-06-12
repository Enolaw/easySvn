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

    private var oldestLoadedRevision: Int?

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

    func load(workingCopy: WorkingCopy) async {
        isLoading = true
        errorMessage = nil
        hasMore = true
        defer { isLoading = false }

        do {
            let client = try SvnClient.detect()
            let loaded = try await client.log(
                at: workingCopy.path,
                limit: Self.pageSize,
                revisionRange: "HEAD:1",
                verbose: true
            )
            entries = loaded
            oldestLoadedRevision = loaded.last?.revision
            selectedRevision = loaded.first?.revision
            hasMore = (oldestLoadedRevision ?? 1) > 1
        } catch let error as SvnError {
            entries = []
            errorMessage = error.message
        } catch SvnKitError.svnNotFound {
            errorMessage = "找不到 svn 命令行工具"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore(workingCopy: WorkingCopy) async {
        guard hasMore, let oldest = oldestLoadedRevision, oldest > 1, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let client = try SvnClient.detect()
            let end = oldest - 1
            let loaded = try await client.log(
                at: workingCopy.path,
                limit: Self.pageSize,
                revisionRange: "\(end):1",
                verbose: true
            )
            let existing = Set(entries.map(\.revision))
            let newOnes = loaded.filter { !existing.contains($0.revision) }
            entries.append(contentsOf: newOnes)
            oldestLoadedRevision = entries.last?.revision
            hasMore = (oldestLoadedRevision ?? 1) > 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyRevision(_ revision: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(revision), forType: .string)
    }
}
