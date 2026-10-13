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

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: QuotaStore.appGroupID)
    }

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
