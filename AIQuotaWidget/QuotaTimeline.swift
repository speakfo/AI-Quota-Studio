//
//  QuotaTimeline.swift
//  AIQuotaWidget
//

import Foundation
import WidgetKit

enum QuotaTimeline {
    /// How often the system should re-read the cache file.
    static let reloadInterval: TimeInterval = 5 * 60
    /// Step of the "ticking" entries: the countdown advances without reloading data.
    static let tickInterval: TimeInterval = 60

    static func build(for provider: QuotaProvider, now: Date = Date()) -> Timeline<QuotaEntry> {
        let result = QuotaStore.load(provider, now: now)
        let error = QuotaStore.loadError(provider)

        // The same snapshot with different dates: until WidgetKit wakes us up
        // for fresh data, the "resets in …" countdowns keep moving.
        let tickCount = Int(reloadInterval / tickInterval)
        let entries = (0..<tickCount).map { step in
            QuotaEntry(date: now.addingTimeInterval(Double(step) * tickInterval), result: result, error: error)
        }

        return Timeline(
            entries: entries,
            policy: .after(now.addingTimeInterval(reloadInterval))
        )
    }
}
