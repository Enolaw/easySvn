import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WorkingCopyStore
    @State private var selection: WorkingCopy.ID?

    private var selectedWorkingCopy: WorkingCopy? {
        store.workingCopies.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let workingCopy = selectedWorkingCopy {
                StatusListView(workingCopy: workingCopy)
            } else {
                emptyPlaceholder
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("工作副本") {
                ForEach(store.workingCopies) { workingCopy in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(workingCopy.name)
                            Text(workingCopy.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } icon: {
                        Image(systemName: "externaldrive.connected.to.line.below")
                    }
                    .tag(workingCopy.id)
                    .contextMenu {
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([workingCopy.directoryURL])
                        }
                        Divider()
                        Button("移除", role: .destructive) {
                            if selection == workingCopy.id { selection = nil }
                            store.remove(workingCopy)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: addWorkingCopy) {
                Label("添加工作副本", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(10)
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("选择或添加一个 SVN 工作副本")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("添加工作副本…", action: addWorkingCopy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addWorkingCopy() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择一个 SVN 工作副本目录"
        panel.prompt = "添加"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.add(directoryURL: url)
        selection = store.workingCopies.first { $0.path == url.path }?.id
    }
}
