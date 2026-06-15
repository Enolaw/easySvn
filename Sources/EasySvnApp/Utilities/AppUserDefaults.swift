import Foundation

/// 统一应用偏好存储。
///
/// `swift run` 与打包 `.app` 的 bundle id 不同，直接写 `UserDefaults.standard`
/// 会落到不同 plist。使用独立的 `com.easysvn.shared` suite（不能等于 bundle id），
/// 并在首次启动时从旧域迁移数据。
@MainActor
enum AppUserDefaults {

    /// 注意：不能设为 `com.easysvn.app`，否则与 bundle id 相同时 macOS 会拒绝创建 suite 并导致崩溃。
    static let suiteName = "com.easysvn.shared"
    private static let migrationFlagKey = "didMigrateLegacyUserDefaults"

    private static let swiftRunSuiteName = "EasySvnApp"

    private static let migratedKeys = [
        "workingCopies",
        "appTheme",
        "appLanguage",
        "externalDiffPreset",
        "externalDiffExecutable",
        "externalDiffArguments",
        "preferExternalDiff",
        "showIgnored",
        "authKnownRealms",
        "trustedCertRealms",
        "autoRefreshEnabled",
        "recentCommitMessages",
    ]

    static let shared: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("无法创建 UserDefaults suite：\(suiteName)")
        }
        migrateLegacyDataIfNeeded(into: defaults)
        return defaults
    }()

    private static func migrateLegacyDataIfNeeded(into target: UserDefaults) {
        guard !target.bool(forKey: migrationFlagKey) else { return }

        // swift run 旧数据在 EasySvnApp 域；打包 .app 旧数据在 standard（com.easysvn.app）
        let sources: [UserDefaults] = [
            UserDefaults(suiteName: swiftRunSuiteName),
            UserDefaults.standard,
        ].compactMap { $0 }

        for key in migratedKeys where target.object(forKey: key) == nil {
            for source in sources {
                if let value = source.object(forKey: key) {
                    target.set(value, forKey: key)
                    break
                }
            }
        }

        target.set(true, forKey: migrationFlagKey)
    }
}
