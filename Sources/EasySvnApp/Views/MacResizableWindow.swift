import AppKit
import SwiftUI

/// 让 SwiftUI sheet / 窗口可拖拽缩放，并给出较大的初始尺寸。
struct MacResizableWindow: NSViewRepresentable {
    var minSize: NSSize
    var idealSize: NSSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView, coordinator: context.coordinator)
        }
    }

    private func configure(_ view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        window.styleMask.insert(.resizable)
        window.minSize = minSize
        guard !coordinator.didSetInitialSize else { return }
        coordinator.didSetInitialSize = true
        window.setContentSize(clampedIdealSize)
    }

    private var clampedIdealSize: NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        return NSSize(
            width: min(max(idealSize.width, minSize.width), max(minSize.width, screen.width - 80)),
            height: min(max(idealSize.height, minSize.height), max(minSize.height, screen.height - 80))
        )
    }

    final class Coordinator {
        var didSetInitialSize = false
    }
}
