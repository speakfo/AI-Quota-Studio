//
//  QuotaWidgetViews.swift
//  AIQuotaWidget
//
//  Shared layout for the Claude Code, Antigravity and Codex widgets.
//

import SwiftUI
import WidgetKit

// MARK: - Palette

extension Color {
    static let amber = Color(red: 0.95, green: 0.65, blue: 0.15)
    static let codexGreen = Color(red: 0.36, green: 0.82, blue: 0.68)
    // Named `quotaBackground`, not `widgetBackground`: the asset catalog already
    // generates `Color.widgetBackground` from WidgetBackground.colorset.
    static let quotaBackground = Color(red: 0.08, green: 0.10, blue: 0.16)

    /// Bar color by remaining quota: the less is left, the more alarming.
    static func quotaLevel(remaining: Double) -> Color {
        switch remaining {
        case ..<15: return Color(red: 0.94, green: 0.33, blue: 0.31)
        case ..<40: return Color(red: 0.95, green: 0.65, blue: 0.15)
        default: return Color(red: 0.30, green: 0.80, blue: 0.50)
        }
    }
}

// MARK: - Timeline entry

struct QuotaEntry: TimelineEntry {
    let date: Date
    let result: QuotaLoadResult
    /// Why the last collection failed; nil — it succeeded.
    var error: CollectorError? = nil
}

// MARK: - Single window row

struct QuotaRowView: View {
    let title: String
    let status: QuotaWindowStatus?
    let now: Date
    var compact: Bool = false
    /// The plan has no such window: the row is dimmed and explains why instead of "no data".
    var missingNote: String? = nil

    private var levelColor: Color {
        guard let status else { return .gray }
        return .quotaLevel(remaining: status.remainingPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                // Show usage, like /usage in Claude Code, so the numbers match
                // and nobody has to subtract in their head.
                Text(compact ? L10n.tr("used (short)") : L10n.tr("used"))
                    .font(.system(size: compact ? 8 : 9))
                    .foregroundColor(.gray)
                if let status {
                    Text(verbatim: "\(Int(status.usedPercent.rounded()))%")
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                        .foregroundColor(levelColor)
                } else {
                    Text(verbatim: "—")
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                        .foregroundColor(.gray)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    if let status {
                        Capsule()
                            .fill(levelColor)
                            .frame(width: geo.size.width * CGFloat(status.usedPercent) / 100)
                    }
                }
            }
            .frame(height: compact ? 5 : 6)

            Text(footnote)
                .font(.system(size: compact ? 8 : 9))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .opacity(status == nil && missingNote != nil ? 0.55 : 1)
    }

    private var footnote: String {
        guard let status else { return missingNote ?? L10n.tr("no data") }
        if status.didResetSinceMeasurement { return L10n.tr("window reset") }
        return L10n.tr("resets in %@", QuotaFormat.countdown(to: status.resetsAt, now: now))
    }
}

// MARK: - Compact single window row (Small widget with several model groups)

struct CompactQuotaRowView: View {
    let title: String
    let status: QuotaWindowStatus?
    let now: Date

    private var levelColor: Color {
        guard let status else { return .gray }
        return .quotaLevel(remaining: status.remainingPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                if let countdown = status.map({ QuotaFormat.countdown(to: $0.resetsAt, now: now) }), countdown != "—" {
                    Text(verbatim: "· \(countdown)")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                if let status {
                    Text(verbatim: "\(Int(status.usedPercent.rounded()))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(levelColor)
                } else {
                    Text(verbatim: "—")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    if let status {
                        Capsule()
                            .fill(levelColor)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(status.usedPercent) / 100)))
                    }
                }
            }
            .frame(height: 3.5)
        }
    }
}

// MARK: - Provider card (Claude Code, Codex)

struct QuotaCardView: View {
    let providerTitle: String
    let accent: Color
    let entry: QuotaEntry
    let family: WidgetFamily
    /// Which windows to show. Defaults to 5 hours and week, even when empty.
    var rows: (QuotaSnapshot) -> [QuotaRow] = { $0.defaultRows }

    private var compact: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : (family == .systemLarge ? 16 : 10)) {
            HStack(alignment: .firstTextBaseline) {
                Text(providerTitle)
                    .font(.system(size: compact ? 13 : (family == .systemLarge ? 17 : 15), weight: .bold))
                    .foregroundColor(accent)
                Spacer()
                StatusBadge(entry: entry, compact: compact)
            }

            if case .missing = entry.result {
                MissingDataView(compact: compact, error: entry.error)
            } else if let snapshot = entry.result.snapshot {
                let items = rows(snapshot)
                ForEach(items.indices, id: \.self) { index in
                    QuotaRowView(
                        title: items[index].title,
                        status: items[index].window?.status(now: entry.date),
                        now: entry.date,
                        compact: compact,
                        missingNote: items[index].missingNote
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Antigravity card (Gemini + Claude & GPT)

struct AntigravityQuotaCardView: View {
    let entry: QuotaEntry
    let family: WidgetFamily

    private var compact: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : (family == .systemLarge ? 14 : 8)) {
            // Widget title (large, to stand out above the model groups)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Antigravity")
                    .font(.system(size: compact ? 13 : (family == .systemLarge ? 17 : 15), weight: .bold))
                    .foregroundColor(.cyan)
                Spacer()
                StatusBadge(entry: entry, compact: compact)
            }

            if case .missing = entry.result {
                MissingDataView(compact: compact, error: entry.error)
            } else {
                let snapshot = entry.result.snapshot

                switch family {
                case .systemSmall:
                    VStack(alignment: .leading, spacing: 4) {
                        // Gemini models block
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 3) {
                                Circle().fill(Color.cyan).frame(width: 4, height: 4)
                                Text(L10n.tr("Gemini models"))
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            CompactQuotaRowView(
                                title: L10n.tr("5h"),
                                status: snapshot?.fiveHour?.status(now: entry.date),
                                now: entry.date
                            )
                            CompactQuotaRowView(
                                title: L10n.tr("7d"),
                                status: snapshot?.sevenDay?.status(now: entry.date),
                                now: entry.date
                            )
                        }

                        // Claude and GPT models block
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 3) {
                                Circle().fill(Color(red: 0.85, green: 0.65, blue: 0.95)).frame(width: 4, height: 4)
                                Text(L10n.tr("Claude and GPT models"))
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            CompactQuotaRowView(
                                title: L10n.tr("5h"),
                                status: snapshot?.fiveHourClaudeGpt?.status(now: entry.date),
                                now: entry.date
                            )
                            CompactQuotaRowView(
                                title: L10n.tr("7d"),
                                status: snapshot?.sevenDayClaudeGpt?.status(now: entry.date),
                                now: entry.date
                            )
                        }
                    }

                case .systemMedium:
                    HStack(alignment: .top, spacing: 12) {
                        // Gemini models column
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.cyan).frame(width: 5, height: 5)
                                Text(L10n.tr("Gemini models"))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            QuotaRowView(
                                title: L10n.tr("5 hours"),
                                status: snapshot?.fiveHour?.status(now: entry.date),
                                now: entry.date,
                                compact: true
                            )
                            QuotaRowView(
                                title: L10n.tr("Week"),
                                status: snapshot?.sevenDay?.status(now: entry.date),
                                now: entry.date,
                                compact: true
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()
                            .opacity(0.2)

                        // Claude and GPT models column
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Circle().fill(Color(red: 0.85, green: 0.65, blue: 0.95)).frame(width: 5, height: 5)
                                Text(L10n.tr("Claude and GPT models"))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            QuotaRowView(
                                title: L10n.tr("5 hours"),
                                status: snapshot?.fiveHourClaudeGpt?.status(now: entry.date),
                                now: entry.date,
                                compact: true
                            )
                            QuotaRowView(
                                title: L10n.tr("Week"),
                                status: snapshot?.sevenDayClaudeGpt?.status(now: entry.date),
                                now: entry.date,
                                compact: true
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                default:
                    // Large
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Circle().fill(Color.cyan).frame(width: 6, height: 6)
                                Text(L10n.tr("Gemini models"))
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.cyan)
                            }
                            QuotaRowView(
                                title: L10n.tr("5 hours"),
                                status: snapshot?.fiveHour?.status(now: entry.date),
                                now: entry.date,
                                compact: false
                            )
                            QuotaRowView(
                                title: L10n.tr("Week"),
                                status: snapshot?.sevenDay?.status(now: entry.date),
                                now: entry.date,
                                compact: false
                            )
                        }

                        Divider()
                            .opacity(0.3)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(red: 0.85, green: 0.65, blue: 0.95)).frame(width: 6, height: 6)
                                Text(L10n.tr("Claude and GPT models"))
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.95))
                            }
                            QuotaRowView(
                                title: L10n.tr("5 hours"),
                                status: snapshot?.fiveHourClaudeGpt?.status(now: entry.date),
                                now: entry.date,
                                compact: false
                            )
                            QuotaRowView(
                                title: L10n.tr("Week"),
                                status: snapshot?.sevenDayClaudeGpt?.status(now: entry.date),
                                now: entry.date,
                                compact: false
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Empty state

struct MissingDataView: View {
    let compact: Bool
    var error: CollectorError? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error?.shortMessage.capitalizingFirstLetter ?? L10n.tr("No data"))
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundColor(error == nil ? .white : .orange)
            Text(hint)
                .font(.system(size: compact ? 8 : 9))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hint: String {
        switch error {
        case .notInstalled:
            return compact ? L10n.tr("Install the CLI") : L10n.tr("Install the CLI and sign in — AI Quota Studio will find it on its own.")
        case .unparsable(let cli):
            return compact ? L10n.tr("Sign in") : L10n.tr("Run %@ in Terminal and sign in.", cli)
        case .noResponse:
            return compact ? L10n.tr("Will retry later") : L10n.tr("AI Quota Studio will retry on the next poll.")
        case nil:
            return compact ? L10n.tr("Open AI Quota Studio") : L10n.tr("Launch AI Quota Studio: it collects quotas from claude, agy and codex.")
        }
    }
}

// MARK: - Header status

/// A failure reason beats the "stale" mark: it explains why the data is old.
struct StatusBadge: View {
    let entry: QuotaEntry
    let compact: Bool

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: compact ? 8 : 9, weight: .medium))
                .foregroundColor(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var text: String? {
        // Without data, MissingDataView already shows the reason.
        if case .missing = entry.result { return nil }
        if let error = entry.error { return error.shortMessage }
        if entry.result.isStale { return compact ? L10n.tr("stale") : L10n.tr("data is stale") }
        return nil
    }
}

private extension String {
    var capitalizingFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Background

extension View {
    /// Desktop widgets clip a plain `.background(...)`; the gradient has
    /// to go through containerBackground to reach the widget surface.
    func quotaContainerBackground() -> some View {
        containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.quotaBackground, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
