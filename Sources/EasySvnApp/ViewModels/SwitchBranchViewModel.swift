import Foundation
import SvnKit

/// 切换工作副本分支（svn switch）。
@MainActor
final class SwitchBranchViewModel: ObservableObject {

    @Published var targetURL = ""
    @Published var currentURL = ""
    @Published private(set) var localChangeCount = 0
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private weak var authStore: AuthSettingsStore?
    private var repositoryRoot = ""

    var canSubmit: Bool {
        !targetURL.isEmpty && targetURL != currentURL && !isWorking
    }

    func configure(authStore: AuthSettingsStore) {
        self.authStore = authStore
    }

    func load(workingCopy: WorkingCopy) async {
        errorMessage = nil
        do {
            let client = try makeClient(for: workingCopy)
            let info = try await client.info(at: workingCopy.directoryURL)
            currentURL = RepositoryURLHelper.displayDecoded(info.url)
            repositoryRoot = RepositoryURLHelper.displayDecoded(info.repositoryRoot)
            let entries = try await client.status(at: workingCopy.directoryURL)
            localChangeCount = entries.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchBranch(workingCopy: WorkingCopy) async -> Bool {
        guard canSubmit else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let client = try makeClient(for: workingCopy)
            let revision = try await client.switchTo(targetURL, in: workingCopy.directoryURL)
            _ = revision
            return true
        } catch let error as SvnError {
            if !handleAuthFailure(error, workingCopy: workingCopy, retry: { [weak self] in
                _ = await self?.switchBranch(workingCopy: workingCopy)
            }) {
                errorMessage = error.message
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func fillBranchURL(name: String, kind: RepositoryCopyKind) {
        guard !name.isEmpty else { return }
        targetURL = RepositoryURLBuilder.destinationURL(
            repositoryRoot: repositoryRoot,
            kind: kind,
            name: name
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
}
