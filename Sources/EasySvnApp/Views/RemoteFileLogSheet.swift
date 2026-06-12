import SwiftUI
import SvnKit

/// 远程文件提交日志（无需打开文件预览）。
struct RemoteFileLogSheet: View {
    let fileURL: String
    let fileName: String
    let workingCopy: WorkingCopy

    @EnvironmentObject private var authStore: AuthSettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [SvnLogEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("提交日志")
                        .font(.headline)
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(16)

            Divider()

            Group {
                if isLoading {
                    ProgressView("正在加载日志…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 10) {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") { Task { await load() } }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    Text("无提交记录")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(entries, id: \.revision) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("r\(entry.revision)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                if let author = entry.author {
                                    Text(author)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let date = entry.date {
                                    Text(date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Text(entry.message)
                                .font(.callout)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(width: 520, height: 420)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = try authStore.makeClient(forRepositoryURL: workingCopy.path)
            entries = try await client.log(
                at: fileURL,
                limit: 50,
                revisionRange: "HEAD:1",
                verbose: false
            )
        } catch let error as SvnError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
