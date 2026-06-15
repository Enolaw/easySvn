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
            let data = AppUserDefaults.shared.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode([WorkingCopy].self, from: data)
        else {
            return
        }
        workingCopies = decoded.map { item in
            var copy = item
            copy.path = WorkingCopyPathNormalizer.normalize(item.path)
            return copy
        }
        if workingCopies != decoded {
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(workingCopies) {
            AppUserDefaults.shared.set(data, forKey: Self.defaultsKey)
        }
    }
}
