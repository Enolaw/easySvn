import AppKit
import SwiftUI

/// 通过 swift run / Xcode 运行可执行 target 时没有 App Bundle，
/// 需要手动设置激活策略让窗口出现在前台和 Dock。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct EasySvnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WorkingCopyStore()
    @StateObject private var authStore = AuthSettingsStore()
    @StateObject private var appSettings = AppSettingsStore()

    var body: some Scene {
        WindowGroup("easySvn") {
            ContentView()
                .environmentObject(store)
                .environmentObject(authStore)
                .environmentObject(appSettings)
                .preferredColorScheme(appSettings.theme.colorScheme)
                .environment(\.locale, appSettings.language.locale ?? Locale.current)
                .frame(minWidth: 760, minHeight: 460)
        }

        Settings {
            SettingsView()
                .environmentObject(authStore)
                .environmentObject(appSettings)
        }
    }
}
