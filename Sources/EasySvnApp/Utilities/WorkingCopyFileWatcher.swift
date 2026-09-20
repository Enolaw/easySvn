import Foundation

/// FSEvents 回调中的 `eventPaths` 是 `char **`（C 字符串指针数组），不是 NSArray。
private func fseventAbsolutePaths(from eventPaths: UnsafeMutableRawPointer, count: Int) -> [String] {
    guard count > 0 else { return [] }
    let pointers = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    return (0..<count).map { String(cString: pointers[$0]) }
}

private func workingCopyFSEventsCallback(
    _: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    _: UnsafePointer<FSEventStreamEventFlags>,
    _: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo, numEvents > 0 else { return }
    let watcher = Unmanaged<WorkingCopyFileWatcher>
        .fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
    let absolute = fseventAbsolutePaths(from: eventPaths, count: numEvents)
    let relative = watcher.relativePaths(from: absolute)
    watcher.scheduleRefresh(relativePaths: relative)
}

/// 使用 FSEvents 监听工作副本目录变更，防抖后回调刷新。
final class WorkingCopyFileWatcher: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.easysvn.fsevents")
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var onChangeHandler: (@MainActor ([String]) -> Void)?
    private var watchedRoot = ""
    private let debounceInterval: TimeInterval = 0.8

    func watch(path: String, onChange: @escaping @MainActor ([String]) -> Void) {
        stop()
        watchedRoot = path
        onChangeHandler = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [path] as CFArray
        let latency: CFTimeInterval = 0.3
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            nil,
            workingCopyFSEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    fileprivate func relativePaths(from absolutePaths: [String]) -> [String] {
        let root = watchedRoot
        guard !root.isEmpty else { return [] }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        var result: [String] = []
        result.reserveCapacity(absolutePaths.count)
        for path in absolutePaths {
            if path == root {
                result.append(".")
            } else if path.hasPrefix(prefix) {
                let relative = String(path.dropFirst(prefix.count))
                result.append(WorkingCopyRelativePath.normalize(relative))
            }
        }
        return Array(Set(result))
    }

    fileprivate func scheduleRefresh(relativePaths: [String]) {
        debounceWorkItem?.cancel()
        let paths = relativePaths
        let work = DispatchWorkItem { [weak self] in
            guard let self, let handler = self.onChangeHandler else { return }
            Task { @MainActor in handler(paths) }
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        watchedRoot = ""
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        onChangeHandler = nil
    }

    deinit {
        stop()
    }
}
