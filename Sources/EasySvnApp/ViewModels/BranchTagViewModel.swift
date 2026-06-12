import Foundation
import SvnKit

/// 创建分支/标签（svn copy）。
@MainActor
final class BranchTagViewModel: ObservableObject {

    @Published var kind: RepositoryCopyKind = .branch
    @Published var sourceURL = ""
    @Published var name = ""
    @Published var message = ""
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private weak var authStore: AuthSettingsStore?
    private var repositoryRoot = ""

    var destinationURL: String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return RepositoryURLBuilder.destinationURL(
            repositoryRoot: repositoryRoot,
            kind: kind,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var canSubmit: Bool {
        !sourceURL.isEmpty && !name.isEmpty && !message.isEmpty && !isWorking
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
            repositoryRoot = info.repositoryRoot
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(workingCopy: WorkingCopy) async -> Bool {
        guard canSubmit else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let dest = destinationURL
        let log = message.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let client = try makeClient(for: workingCopy)
            _ = try await client.copyBranchOrTag(
                from: sourceURL,
                to: dest,
                kind: kind,
                repositoryRoot: repositoryRoot,
                message: log
            )
            return true
        } catch let error as SvnError {
            if !handleAuthFailure(error, workingCopy: workingCopy, retry: { [weak self] in
                _ = await self?.create(workingCopy: workingCopy)
            }) {
                errorMessage = error.message
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func applySuggestedName() {
        guard !name.isEmpty else { return }
        if message.isEmpty {
            message = "创建\(kind.displayName) \(name)"
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
