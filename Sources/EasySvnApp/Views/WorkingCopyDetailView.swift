import SwiftUI

private enum WorkingCopyTab: String, CaseIterable, Identifiable {
    case status = "变更"
    case log = "日志"
    case repo = "仓库"

    var id: String { rawValue }
}

private enum BranchSheet: Identifiable {
    case branchTag
    case switchBranch
    case merge

    var id: String {
        switch self {
        case .branchTag: "branchTag"
        case .switchBranch: "switchBranch"
        case .merge: "merge"
        }
    }
}

/// 工作副本详情：变更列表 + 日志 + 仓库浏览器 + 分支/合并操作。
struct WorkingCopyDetailView: View {
    let workingCopy: WorkingCopy

    @EnvironmentObject private var store: WorkingCopyStore
    @EnvironmentObject private var authStore: AuthSettingsStore
    @State private var tab: WorkingCopyTab = .status
    @State private var refreshToken = UUID()
    @State private var activeSheet: BranchSheet?
    @StateObject private var branchTagViewModel = BranchTagViewModel()
    @StateObject private var switchBranchViewModel = SwitchBranchViewModel()
    @StateObject private var mergeWizardViewModel = MergeWizardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(WorkingCopyTab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer()

                Menu {
                    Button("创建分支/标签…") { openSheet(.branchTag) }
                    Button("切换分支…") { openSheet(.switchBranch) }
                    Divider()
                    Button("合并…") { openSheet(.merge) }
                } label: {
                    Label("分支", systemImage: "arrow.triangle.branch")
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            switch tab {
            case .status:
                StatusListView(workingCopy: workingCopy, refreshToken: refreshToken)
                    .id(workingCopy.id)
            case .log:
                LogView(workingCopy: workingCopy)
            case .repo:
                RepoBrowserView(workingCopy: workingCopy) { url in
                    store.add(directoryURL: url)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .branchTag:
                BranchTagSheet(workingCopy: workingCopy, viewModel: branchTagViewModel, onComplete: refreshWorkingCopy)
                    .onAppear { branchTagViewModel.configure(authStore: authStore) }
            case .switchBranch:
                SwitchBranchSheet(workingCopy: workingCopy, viewModel: switchBranchViewModel, onComplete: refreshWorkingCopy)
                    .onAppear { switchBranchViewModel.configure(authStore: authStore) }
            case .merge:
                MergeWizardSheet(workingCopy: workingCopy, viewModel: mergeWizardViewModel, onComplete: refreshWorkingCopy)
                    .onAppear { mergeWizardViewModel.configure(authStore: authStore) }
            }
        }
    }

    private func openSheet(_ sheet: BranchSheet) {
        activeSheet = sheet
    }

    private func refreshWorkingCopy() async {
        refreshToken = UUID()
    }
}
