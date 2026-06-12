import Foundation
import SvnKit

/// 合并模式。
enum MergeMode: String, CaseIterable, Identifiable {
    case branch
    case revisionRange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .branch: "合并整个分支"
        case .revisionRange: "合并版本范围"
        }
    }
}

/// Merge 向导：dry-run 预览、执行合并、mergeinfo 查询。
@MainActor
final class MergeWizardViewModel: ObservableObject {

    @Published var mode: MergeMode = .branch
    @Published var sourceURL = ""
    @Published var revisionFrom = ""
    @Published var revisionTo = "HEAD"
    @Published private(set) var dryRunResult = ""
    @Published private(set) var mergedRevisions: [Int] = []
    @Published private(set) var eligibleRevisions: [Int] = []
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private weak var authStore: AuthSettingsStore?

    var revisionRange: String? {
        guard mode == .revisionRange else { return nil }
        let from = revisionFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = revisionTo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return nil }
        return "\(from):\(to)"
    }

    var canMerge: Bool {
        !sourceURL.isEmpty && !isWorking && (mode == .branch || revisionRange != nil)
    }

    func configure(authStore: AuthSettingsStore) {
        self.authStore = authStore
    }

    func load(workingCopy: WorkingCopy) async {
        errorMessage = nil
        do {
            let client = try makeClient(for: workingCopy)
            let info = try await client.info(at: workingCopy.directoryURL)
            sourceURL = info.url
            await refreshMergeinfo(workingCopy: workingCopy)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshMergeinfo(workingCopy: WorkingCopy) async {
        guard !sourceURL.isEmpty else { return }
        do {
            let client = try makeClient(for: workingCopy)
            mergedRevisions = try await client.mergeinfo(
                source: sourceURL,
                kind: .merged,
                in: workingCopy.directoryURL
            )
            eligibleRevisions = try await client.mergeinfo(
                source: sourceURL,
                kind: .eligible,
                in: workingCopy.directoryURL
            )
        } catch {
            mergedRevisions = []
            eligibleRevisions = []
        }
    }

    func dryRun(workingCopy: WorkingCopy) async {
        guard canMerge else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let client = try makeClient(for: workingCopy)
            dryRunResult = try await client.merge(
                source: sourceURL,
                in: workingCopy.directoryURL,
                revisionRange: revisionRange,
                dryRun: true
            )
            if dryRunResult.isEmpty {
                dryRunResult = "（无变更，或已全部合并）"
            }
        } catch let error as SvnError {
            if !handleAuthFailure(error, workingCopy: workingCopy, retry: { [weak self] in
                await self?.dryRun(workingCopy: workingCopy)
            }) {
                errorMessage = error.message
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func merge(workingCopy: WorkingCopy) async -> Bool {
        guard canMerge else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let client = try makeClient(for: workingCopy)
            _ = try await client.merge(
                source: sourceURL,
                in: workingCopy.directoryURL,
                revisionRange: revisionRange,
                dryRun: false
            )
            await refreshMergeinfo(workingCopy: workingCopy)
            return true
        } catch let error as SvnError {
            // 合并产生冲突时 svn 可能非零退出，但合并已部分应用
            if error.code == nil || error.message.localizedCaseInsensitiveContains("conflict") {
                await refreshMergeinfo(workingCopy: workingCopy)
                errorMessage = "合并完成但存在冲突，请在变更列表中解决"
                return true
            }
            if !handleAuthFailure(error, workingCopy: workingCopy, retry: { [weak self] in
                _ = await self?.merge(workingCopy: workingCopy)
            }) {
                errorMessage = error.message
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
