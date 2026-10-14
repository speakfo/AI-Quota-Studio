//
//  QuotaConfig.swift
//  Shared
//
//  Background refresh interval setting.
//

import Foundation

enum QuotaConfig {
    static let defaultIntervalMinutes: Int = 5
    private static let intervalKey = "refreshIntervalMinutes"

    /// Only the app reads this, so its own defaults are enough.
    private static var defaults: UserDefaults? { .standard }

    /// Background polling interval in minutes (5 by default).
    static var refreshIntervalMinutes: Int {
        get {
            let val = defaults?.integer(forKey: intervalKey) ?? 0
            return val > 0 ? val : defaultIntervalMinutes
        }
        set {
            defaults?.set(newValue, forKey: intervalKey)
        }
    }

    /// Interval in seconds.
    static var refreshIntervalSeconds: Int {
        refreshIntervalMinutes * 60
    }
}
