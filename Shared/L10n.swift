//
//  L10n.swift
//  Shared
//
//  In-app language selection shared by the app and the widget.
//

import Foundation

/// Interface languages the user can pick in Settings.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    /// Always in its own language, so it stays recognizable whatever is selected.
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

/// String lookup in the language chosen in Settings rather than the system one.
///
/// Translations live in `Shared/Localizable.xcstrings`; keys are the English
/// text. The choice is stored in the App Group defaults so the sandboxed widget
/// renders in the same language as the menu.
nonisolated enum L10n {
    static let languageKey = "appLanguage"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: QuotaStore.appGroupID)
    }

    /// English unless the user picked something else.
    static var language: AppLanguage {
        get { defaults?.string(forKey: languageKey).flatMap(AppLanguage.init) ?? .english }
        set { defaults?.set(newValue.rawValue, forKey: languageKey) }
    }

    static func tr(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: language.locale, arguments: arguments)
    }

    /// The `.lproj` of the selected language; Foundation caches these bundles.
    private static var bundle: Bundle {
        Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
    }
}
