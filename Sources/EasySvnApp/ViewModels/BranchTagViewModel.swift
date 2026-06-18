import Foundation
import SvnKit

/// 创建分支/标签（svn copy）。
@MainActor
final class BranchTagViewModel: ObservableObject {

    @Published var kind: RepositoryCopyKind = .branch
    @Published var sourceURL = ""
    @Published var name = ""
    @Published var destinationURL = ""
    @Published var message = ""
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private weak var authStore: AuthSettingsStore?
    private var repositoryRoot = ""
    private var destinationEditedByUser = false

    var canSubmit: Bool {
        !sourceURL.isEmpty
            && !sanitizedName.isEmpty
            && !destinationURL.isEmpty
            && !message.isEmpty
            && !isWorking
    }

    private var sanitizedName: String {
        RepositoryURLBuilder.sanitizeCopyName(name)
    }

    func configure(authStore: AuthSettingsStore) {
        self.authStore = authStore
    }

    func load(workingCopy: WorkingCopy) async {
        errorMessage = nil
        destinationEditedByUser = false
        do {
            let client = try makeClient(for: workingCopy)
            let info = try await client.info(at: workingCopy.directoryURL)
            sourceURL = RepositoryURLHelper.displayDecoded(info.url)
            repositoryRoot = RepositoryURLHelper.displayDecoded(info.repositoryRoot)
            name = RepositoryURLHelper.lastComponent(of: info.url)
            applySuggestedDestination()
            applySuggestedName()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(workingCopy: WorkingCopy) async -> Bool {
        guard canSubmit else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let dest = RepositoryURLBuilder.resolvedCopyDestination(
            baseURL: destinationURL,
            name: sanitizedName
        )
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

    func onKindChanged() {
        destinationEditedByUser = false
        applySuggestedDestination()
        applySuggestedName()
    }

    func normalizeName() {
        let sanitized = sanitizedName
        if sanitized != name {
            name = sanitized
        }
        applySuggestedDestination()
        applySuggestedName()
    }

    func onSourceURLChanged() {
        destinationEditedByUser = false
        applySuggestedDestination()
    }

    func onDestinationEdited() {
        destinationEditedByUser = true
    }

    func applySuggestedName() {
        let label = sanitizedName.isEmpty ? name : sanitizedName
        guard !label.isEmpty else { return }
        if message.isEmpty || message.hasPrefix("创建") {
            message = "创建\(kind.displayName) \(label)"
        }
    }

    private func applySuggestedDestination() {
        guard !destinationEditedByUser else { return }
        destinationURL = RepositoryURLBuilder.inferredDestinationURL(
            sourceURL: sourceURL,
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
