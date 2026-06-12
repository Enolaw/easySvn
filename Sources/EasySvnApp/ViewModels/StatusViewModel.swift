import Foundation
import SwiftUI
import SvnKit

/// 工作副本状态视图的数据加载。
@MainActor
final class StatusViewModel: ObservableObject {

    @Published private(set) var info: SvnInfo?
    @Published private(set) var entries: [SvnStatusEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func refresh(workingCopy: WorkingCopy) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = try SvnClient.detect()
            async let info = client.info(at: workingCopy.directoryURL)
            async let entries = client.status(at: workingCopy.directoryURL)
            self.info = try await info
            self.entries = (try await entries).sorted { $0.path < $1.path }
        } catch let error as SvnError {
            self.info = nil
            self.entries = []
            errorMessage = friendlyMessage(for: error)
        } catch SvnKitError.svnNotFound {
            errorMessage = "找不到 svn 命令行工具，请先安装：brew install subversion"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendlyMessage(for error: SvnError) -> String {
        switch error.code {
        case SvnError.Code.notAWorkingCopy:
            return "该目录不是 SVN 工作副本"
        case SvnError.Code.workingCopyLocked:
            return "工作副本被锁定，请执行 Cleanup 后重试"
        default:
            return error.message
        }
    }
}
