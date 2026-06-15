import AppKit
import SwiftUI

/// 应用内统一的面板背景色。
enum AppSurfaceColors {

    /// 侧栏 / 目录树等窄面板背景（介于系统 sidebar 与纯白之间）。
    static var sidebar: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedWhite: isDark ? 0.14 : 0.94, alpha: 1)
        })
    }

    /// 仓库浏览器右侧目录/详情区（比侧栏略浅）。
    static var repoDirectory: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedWhite: isDark ? 0.18 : 0.97, alpha: 1)
        })
    }

    /// 主内容区背景。
    static var content: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    /// 面板顶栏（比内容区略深一点，与侧栏同色系）。
    static var chromeBar: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedWhite: isDark ? 0.16 : 0.97, alpha: 1)
        })
    }
}
