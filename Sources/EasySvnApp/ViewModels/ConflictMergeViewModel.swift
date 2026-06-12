import Foundation
import SvnKit

/// 三方合并视图数据与操作。
@MainActor
final class ConflictMergeViewModel: ObservableObject {

    let path: String
    let isTreeConflict: Bool

    @Published private(set) var versions = ConflictVersions()
    @Published private(set) var treeConflict: SvnTreeConflict?
    @Published var resultText = ""
    @Published private(set) var hunks: [ConflictHunk] = []
    @Published var hunkChoices: [Int: ConflictHunkChoice] = [:]
    @Published var currentHunkIndex = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var operationMessage: String?

    private weak var authStore: AuthSettingsStore?

    init(path: String, isTreeConflict: Bool) {
        self.path = path
        self.isTreeConflict = isTreeConflict
    }

    func configure(authStore: AuthSettingsStore) {
        self.authStore = authStore
    }

    var currentHunk: ConflictHunk? {
        guard hunks.indices.contains(currentHunkIndex) else { return nil }
        return hunks[currentHunkIndex]
    }

    func load(workingCopy: WorkingCopy) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = try makeClient(for: workingCopy)
            versions = client.conflictVersions(for: path, in: workingCopy.directoryURL)

            if isTreeConflict {
                let fileURL = workingCopy.directoryURL.appendingPathComponent(path)
                let info = try await client.info(at: fileURL)
                treeConflict = info.treeConflict
            }

            let working = versions.working ?? ""
            resultText = working
            hunks = ConflictMarkerParser.parse(working)
            hunkChoices = Dictionary(uniqueKeysWithValues: hunks.map { ($0.id, ConflictHunkChoice.unresolved) })
            currentHunkIndex = 0
        } catch let error as SvnError {
            if !handleAuthFailure(error, workingCopy: workingCopy) {
                errorMessage = error.message
            }
        } catch SvnKitError.svnNotFound {
            errorMessage = "找不到 svn 命令行工具"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseMineForCurrentHunk() {
        applyChoice(.mine)
    }

    func chooseTheirsForCurrentHunk() {
        applyChoice(.theirs)
    }

    func applyChoice(_ choice: ConflictHunkChoice) {
        guard let hunk = currentHunk else { return }
        hunkChoices[hunk.id] = choice
        if let working = versions.working {
            resultText = ConflictMarkerParser.mergedText(
                original: working,
                hunks: hunks,
                choices: hunkChoices
            )
        }
    }

    func saveAndResolve(workingCopy: WorkingCopy) async -> Bool {
        isLoading = true
        operationMessage = nil
        defer { isLoading = false }

        do {
            let client = try makeClient(for: workingCopy)
            try client.writeConflictResult(resultText, for: path, in: workingCopy.directoryURL)
            try await client.markResolved(paths: [path], in: workingCopy.directoryURL)
            operationMessage = "已保存并标记为已解决"
            return true
        } catch let error as SvnError {
            if !handleAuthFailure(error, workingCopy: workingCopy, retry: { [weak self] in
                _ = await self?.saveAndResolve(workingCopy: workingCopy)
            }) {
                errorMessage = error.message
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func resolve(workingCopy: WorkingCopy, accept: SvnResolveAccept) async -> Bool {
        isLoading = true
        operationMessage = nil
        defer { isLoading = false }

        do {
            let client = try makeClient(for: workingCopy)
            try await client.resolve(paths: [path], accept: accept, in: workingCopy.directoryURL)
            operationMessage = accept.displayName
            return true
        } catch let error as SvnError {
            if !handleAuthFailure(error, workingCopy: workingCopy, retry: { [weak self] in
                _ = await self?.resolve(workingCopy: workingCopy, accept: accept)
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
        retry: (() async -> Void)? = nil
    ) -> Bool {
        guard let authStore else { return false }
        let prompt = authStore.shouldPrompt(for: error, repositoryURL: workingCopy.path)
        guard prompt.needsPrompt else { return false }
        authStore.presentAuthPrompt(
            repositoryURL: workingCopy.path,
            needsCertTrust: prompt.needsCertTrust
        ) {
            if let retry { await retry() }
        }
        return true
    }
}
