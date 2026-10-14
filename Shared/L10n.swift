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
/// text. The app keeps the choice in its own defaults (`@AppStorage` redraws
/// the UI right away) and mirrors it to `settings.json` next to the quota
/// files, where the sandboxed widget reads it.
nonisolated enum L10n {
    static let languageKey = "appLanguage"
    private static let settingsFileName = "settings.json"

    /// The app's defaults; empty in the widget, which falls back to the file.
    static var defaults: UserDefaults { .standard }

    private struct Settings: Codable {
        var language: String?
    }

    private static var settingsURL: URL? {
        QuotaStore.directory?.appendingPathComponent(settingsFileName)
    }

    /// English unless the user picked something else.
    static var language: AppLanguage {
        get {
            let code = defaults.string(forKey: languageKey) ?? languageFromFile()
            return code.flatMap(AppLanguage.init) ?? .english
        }
        set {
            defaults.set(newValue.rawValue, forKey: languageKey)
            guard let url = settingsURL,
                  let data = try? JSONEncoder().encode(Settings(language: newValue.rawValue)) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func languageFromFile() -> String? {
        guard let url = settingsURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Settings.self, from: data))?.language
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
