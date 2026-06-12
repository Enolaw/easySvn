import SwiftUI

private enum WorkingCopyTab: String, CaseIterable, Identifiable {
    case status = "变更"
    case log = "日志"

    var id: String { rawValue }
}

/// 工作副本详情：变更列表 + 提交日志。
struct WorkingCopyDetailView: View {
    let workingCopy: WorkingCopy

    @State private var tab: WorkingCopyTab = .status

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(WorkingCopyTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            switch tab {
            case .status:
                StatusListView(workingCopy: workingCopy)
            case .log:
                LogView(workingCopy: workingCopy)
            }
        }
    }
}
