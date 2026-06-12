import Foundation
import SwiftUI

/// 工作副本书签列表，持久化到 UserDefaults。
@MainActor
final class WorkingCopyStore: ObservableObject {

    private static let defaultsKey = "workingCopies"

    @Published private(set) var workingCopies: [WorkingCopy] = []

    init() {
        load()
    }

    func add(directoryURL: URL) {
        // 已存在则不重复添加
        guard !workingCopies.contains(where: { $0.path == directoryURL.path }) else { return }
        workingCopies.append(WorkingCopy(directoryURL: directoryURL))
        save()
    }

    func remove(_ workingCopy: WorkingCopy) {
        workingCopies.removeAll { $0.id == workingCopy.id }
        save()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode([WorkingCopy].self, from: data)
        else {
            return
        }
        workingCopies = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(workingCopies) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
