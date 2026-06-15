import Foundation
import SwiftUI

/// 外观主题。
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 界面语言（完整文案国际化在 M4 完成，此处先持久化偏好）。
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }
}

/// 外部 diff 工具预设。
enum ExternalDiffPreset: String, CaseIterable, Identifiable, Codable {
    case none
    case fileMerge
    case beyondCompare
    case kaleidoscope
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "不使用"
        case .fileMerge: "FileMerge (opendiff)"
        case .beyondCompare: "Beyond Compare"
        case .kaleidoscope: "Kaleidoscope"
        case .custom: "自定义"
        }
    }

    var defaultExecutable: String {
        switch self {
        case .none: ""
        case .fileMerge: "/usr/bin/opendiff"
        case .beyondCompare: "/Applications/Beyond Compare.app/Contents/MacOS/bcomp"
        case .kaleidoscope: "/Applications/Kaleidoscope.app/Contents/Resources/bin/ksdiff"
        case .custom: ""
        }
    }

    var defaultArguments: String {
        switch self {
        case .none: ""
        default: "%left %right"
        }
    }
}

/// 通用与外部工具设置。
@MainActor
final class AppSettingsStore: ObservableObject {

    private static let themeKey = "appTheme"
    private static let languageKey = "appLanguage"
    private static let diffPresetKey = "externalDiffPreset"
    private static let diffExecutableKey = "externalDiffExecutable"
    private static let diffArgumentsKey = "externalDiffArguments"
    private static let preferExternalDiffKey = "preferExternalDiff"
    private static let showIgnoredKey = "showIgnored"

    @Published var theme: AppTheme {
        didSet { persist(theme, key: Self.themeKey) }
    }
    @Published var language: AppLanguage {
        didSet { persist(language, key: Self.languageKey) }
    }
    @Published var externalDiffPreset: ExternalDiffPreset {
        didSet {
            persist(externalDiffPreset, key: Self.diffPresetKey)
            applyDiffPresetDefaultsIfNeeded()
        }
    }
    @Published var externalDiffExecutable: String {
        didSet { AppUserDefaults.shared.set(externalDiffExecutable, forKey: Self.diffExecutableKey) }
    }
    @Published var externalDiffArguments: String {
        didSet { AppUserDefaults.shared.set(externalDiffArguments, forKey: Self.diffArgumentsKey) }
    }
    @Published var preferExternalDiff: Bool {
        didSet { AppUserDefaults.shared.set(preferExternalDiff, forKey: Self.preferExternalDiffKey) }
    }
    /// 变更列表是否显示 svn:ignore 匹配项。
    @Published var showIgnored: Bool {
        didSet { AppUserDefaults.shared.set(showIgnored, forKey: Self.showIgnoredKey) }
    }

    var hasExternalDiffTool: Bool {
        externalDiffPreset != .none && !externalDiffExecutable.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {
        theme = Self.load(AppTheme.self, key: Self.themeKey, default: .system)
        language = Self.load(AppLanguage.self, key: Self.languageKey, default: .system)
        externalDiffPreset = Self.load(ExternalDiffPreset.self, key: Self.diffPresetKey, default: .none)
        externalDiffExecutable = AppUserDefaults.shared.string(forKey: Self.diffExecutableKey) ?? ""
        externalDiffArguments = AppUserDefaults.shared.string(forKey: Self.diffArgumentsKey)
            ?? ExternalDiffPreset.none.defaultArguments
        if AppUserDefaults.shared.object(forKey: Self.preferExternalDiffKey) == nil {
            preferExternalDiff = false
        } else {
            preferExternalDiff = AppUserDefaults.shared.bool(forKey: Self.preferExternalDiffKey)
        }
        if AppUserDefaults.shared.object(forKey: Self.showIgnoredKey) == nil {
            showIgnored = false
        } else {
            showIgnored = AppUserDefaults.shared.bool(forKey: Self.showIgnoredKey)
        }
        applyDiffPresetDefaultsIfNeeded()
    }

    func applyDiffPreset(_ preset: ExternalDiffPreset) {
        externalDiffPreset = preset
        if preset != .custom {
            externalDiffExecutable = preset.defaultExecutable
            externalDiffArguments = preset.defaultArguments
        }
    }

    private func applyDiffPresetDefaultsIfNeeded() {
        guard externalDiffPreset != .custom, externalDiffPreset != .none else { return }
        if externalDiffExecutable.isEmpty {
            externalDiffExecutable = externalDiffPreset.defaultExecutable
        }
        if externalDiffArguments.isEmpty {
            externalDiffArguments = externalDiffPreset.defaultArguments
        }
    }

    private func persist<T: RawRepresentable>(_ value: T, key: String) where T.RawValue == String {
        AppUserDefaults.shared.set(value.rawValue, forKey: key)
    }

    private static func load<T: RawRepresentable>(
        _ type: T.Type,
        key: String,
        default defaultValue: T
    ) -> T where T.RawValue == String {
        guard let raw = AppUserDefaults.shared.string(forKey: key),
              let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }
}
