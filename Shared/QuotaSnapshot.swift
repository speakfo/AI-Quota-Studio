//
//  QuotaSnapshot.swift
//  Shared
//
//  Quota cache model.
//

import Foundation

/// One limit window — 5-hour, weekly or monthly.
struct QuotaWindow: Codable {
    /// Share of the quota used, 0…100.
    let usedPercentage: Double
    /// When the window resets. nil — the source did not say.
    let resetsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

/// Quota snapshot of one provider.
struct QuotaSnapshot: Codable {
    /// When the collector wrote the data.
    let updatedAt: Date
    /// Who wrote it: "claude-usage", "antigravity-usage", …
    let source: String?
    let windows: [String: QuotaWindow]

    private enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case source
        case windows
    }

    static let fiveHourKey = "five_hour"
    static let sevenDayKey = "seven_day"
    static let fiveHourClaudeGptKey = "five_hour_claude_gpt"
    static let sevenDayClaudeGptKey = "seven_day_claude_gpt"
    /// Monthly window — the Codex free plan has one.
    static let thirtyDayKey = "thirty_day"

    /// Main 5-hour quota (Claude Code, or Gemini models in Antigravity).
    var fiveHour: QuotaWindow? { windows[Self.fiveHourKey] }
    /// Main weekly quota (Claude Code, or Gemini models in Antigravity).
    var sevenDay: QuotaWindow? { windows[Self.sevenDayKey] }

    /// 5-hour quota for Claude & GPT models in Antigravity.
    var fiveHourClaudeGpt: QuotaWindow? { windows[Self.fiveHourClaudeGptKey] }
    /// Weekly quota for Claude & GPT models in Antigravity.
    var sevenDayClaudeGpt: QuotaWindow? { windows[Self.sevenDayClaudeGptKey] }
    /// Monthly quota (Codex free plan).
    var thirtyDay: QuotaWindow? { windows[Self.thirtyDayKey] }

    /// Default rows: 5 hours and week, even when the windows are missing.
    var defaultRows: [QuotaRow] {
        [QuotaRow(title: L10n.tr("5 hours"), window: fiveHour), QuotaRow(title: L10n.tr("Week"), window: sevenDay)]
    }

    /// Codex: the "5 hours" row is always there — the free plan has no such window,
    /// and instead of a gap the row explains why. Longer windows only when present:
    /// week on Plus/Pro, month on the free plan.
    var codexRows: [QuotaRow] {
        var rows = [QuotaRow(title: L10n.tr("5 hours"), window: fiveHour, missingNote: L10n.tr("not in your plan"))]
        if let sevenDay { rows.append(QuotaRow(title: L10n.tr("Week"), window: sevenDay)) }
        if let thirtyDay { rows.append(QuotaRow(title: L10n.tr("Month"), window: thirtyDay)) }
        return rows
    }

    /// Whether there is data for Claude & GPT models (Opus, Sonnet, GPT-OSS).
    var hasClaudeGpt: Bool {
        fiveHourClaudeGpt != nil || sevenDayClaudeGpt != nil
    }

    func age(now: Date = Date()) -> TimeInterval { now.timeIntervalSince(updatedAt) }
}

/// A card row: the window and what to say when it is missing.
struct QuotaRow {
    let title: String
    let window: QuotaWindow?
    /// Shown instead of numbers when the plan has no such window, as opposed to a failure.
    var missingNote: String? = nil
}

/// Display-ready numbers of one window.
struct QuotaWindowStatus {
    let remainingPercent: Double
    let usedPercent: Double
    let resetsAt: Date?
    /// Measured before the reset point, which has already passed.
    let didResetSinceMeasurement: Bool
}

extension QuotaWindow {
    func status(now: Date = Date()) -> QuotaWindowStatus {
        if let resetsAt, resetsAt <= now {
            return QuotaWindowStatus(
                remainingPercent: 100,
                usedPercent: 0,
                resetsAt: nil,
                didResetSinceMeasurement: true
            )
        }
        let used = min(max(usedPercentage, 0), 100)
        return QuotaWindowStatus(
            remainingPercent: 100 - used,
            usedPercent: used,
            resetsAt: resetsAt,
            didResetSinceMeasurement: false
        )
    }
}

enum QuotaFormat {
    /// "3d 12h" / "2h 44m" / "9m". A dash for nil.
    static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return L10n.tr("now") }
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 { return L10n.tr("%lldd %lldh", days, hours % 24) }
        if hours > 0 { return L10n.tr("%lldh %lldm", hours, minutes % 60) }
        return L10n.tr("%lldm", max(minutes, 1))
    }

    /// "just now" / "12 min ago" / "3 h ago" / "2 d ago".
    static func age(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes < 2 { return L10n.tr("just now") }
        if minutes < 60 { return L10n.tr("%lld min ago", minutes) }
        let hours = minutes / 60
        if hours < 24 { return L10n.tr("%lld h ago", hours) }
        return L10n.tr("%lld d ago", hours / 24)
    }
}

extension QuotaSnapshot {
    /// Synthetic data for previews and the widget placeholder.
    static var preview: QuotaSnapshot {
        let now = Date()
        return QuotaSnapshot(
            updatedAt: now.addingTimeInterval(-4 * 60),
            source: "preview",
            windows: [
                fiveHourKey: QuotaWindow(
                    usedPercentage: 47,
                    resetsAt: now.addingTimeInterval(2 * 3600 + 44 * 60)
                ),
                sevenDayKey: QuotaWindow(
                    usedPercentage: 72,
                    resetsAt: now.addingTimeInterval(3 * 86400 + 12 * 3600)
                ),
                fiveHourClaudeGptKey: QuotaWindow(
                    usedPercentage: 56,
                    resetsAt: now.addingTimeInterval(3 * 3600 + 10 * 60)
                ),
                sevenDayClaudeGptKey: QuotaWindow(
                    usedPercentage: 32,
                    resetsAt: now.addingTimeInterval(5 * 86400 + 6 * 3600)
                )
            ]
        )
    }
}
