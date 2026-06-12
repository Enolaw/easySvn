import AppKit
import Foundation
import SwiftUI
import SvnKit

/// Checkout 向导状态与执行逻辑。
@MainActor
final class CheckoutViewModel: ObservableObject {

    @Published var repositoryURL = ""
    @Published var destinationPath = ""
    @Published var revision = ""
    @Published var useSpecificRevision = false
    @Published var depth: SvnDepth = .infinity
    @Published private(set) var progressText = ""
    @Published private(set) var isCheckingOut = false
    @Published var errorMessage: String?

    private var checkoutTask: Task<URL?, Error>?
    private weak var authStore: AuthSettingsStore?

    func configure(authStore: AuthSettingsStore) {
        self.authStore = authStore
    }

    var canCheckout: Bool {
        !repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !destinationPath.isEmpty
            && !isCheckingOut
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择检出目标目录（可为空目录或新建目录）"
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationPath = url.path
    }

    func checkout() async -> URL? {
        guard canCheckout, let authStore else { return nil }

        let url = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = URL(fileURLWithPath: destinationPath)
        let revisionArg: String? = {
            guard useSpecificRevision else { return nil }
            let trimmed = revision.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        if FileManager.default.fileExists(atPath: destination.path) {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: destination.path),
               !contents.isEmpty {
                errorMessage = "目标目录必须为空"
                return nil
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                errorMessage = "无法创建目标目录：\(error.localizedDescription)"
                return nil
            }
        }

        isCheckingOut = true
        errorMessage = nil
        progressText = "正在连接仓库…"
        defer {
            isCheckingOut = false
            checkoutTask = nil
        }

        return await performCheckout(
            authStore: authStore,
            repositoryURL: url,
            destination: destination,
            revision: revisionArg
        )
    }

    func cancel() {
        checkoutTask?.cancel()
        progressText = "已取消"
    }

    private func performCheckout(
        authStore: AuthSettingsStore,
        repositoryURL: String,
        destination: URL,
        revision: String?
    ) async -> URL? {
        do {
            let client = try authStore.makeClient(forRepositoryURL: repositoryURL)
            checkoutTask = Task { @MainActor in
                try await client.checkout(
                    repository: repositoryURL,
                    to: destination,
                    revision: revision,
                    depth: depth
                ) { [weak self] line in
                    Task { @MainActor in
                        self?.progressText = line
                    }
                }
                return destination
            }
            if let result = try await checkoutTask?.value {
                progressText = "检出完成"
                return result
            }
            return nil
        } catch is CancellationError {
            progressText = "已取消"
            return nil
        } catch {
            let prompt = authStore.shouldPrompt(for: error, repositoryURL: repositoryURL)
            if prompt.needsPrompt {
                authStore.presentAuthPrompt(
                    repositoryURL: repositoryURL,
                    needsCertTrust: prompt.needsCertTrust
                ) { [weak self] in
                    _ = await self?.performCheckout(
                        authStore: authStore,
                        repositoryURL: repositoryURL,
                        destination: destination,
                        revision: revision
                    )
                }
                errorMessage = prompt.needsCertTrust
                    ? "需要信任服务器证书或提供凭据"
                    : "认证失败，请输入用户名和密码"
            } else {
                errorMessage = Self.friendlyMessage(for: error)
            }
            return nil
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let svnError = error as? SvnError {
            return svnError.message
        }
        if case SvnKitError.svnNotFound = error {
            return "找不到 svn 命令行工具，请先安装：brew install subversion"
        }
        return error.localizedDescription
    }
}
